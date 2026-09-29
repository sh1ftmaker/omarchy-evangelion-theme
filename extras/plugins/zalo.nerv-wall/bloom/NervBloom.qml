import QtQuick
import QtQuick.Window

// NervBloom — a cheap port of SE Natural Bloom & Dirty Lens (sonicether, MIT, see
// LICENSE-SE-Natural-Bloom) for the NERV desktop wall.
//
// USAGE: put it ABOVE the wall content, same geometry (pixel-aligned):
//
//   Item { id: wall; anchors.fill: parent; /* panels, transparent background */ }
//   NervBloom { anchors.fill: parent; source: wall }
//
// composite: true (default) - the wall is rendered ONCE, into a full-res texture (hideSource), and
//   NervBloom draws wall + glow in one full-res pass. Best when the wall scene is complex.
// composite: false - the wall keeps drawing itself; it is rendered a SECOND time into a
//   captureScale-sized texture and NervBloom draws only the glow layer over it.
// enabled: false unloads the whole chain (textures freed, source visible again) = exact passthrough.
//
// Pipeline (6 octaves, 13 passes, only the last one is full-res):
//   cap   ShaderEffectSource of `source`, RGBA8: full res (composite) or captureScale (overlay)
//   D1    prefilter: un-premultiply -> inverse-tonemap LDR "heat" to HDR -> dual-filter 5-tap down  (1/4)
//   D2-D6 dual-filter 5-tap down, RGBA16F                                            (1/8 .. 1/128)
//   U5-U1 4-tap tent up + accumulate w_k*D_k (rgb = bloom weights pow(i+1,scatter), a = lens-dirt
//         weights, wide octaves add carmine halation), RGBA16F
//   final full-res: tent(U1), SE composite as a premultiplied layer + lens dirt + soft shoulder,
//         "over" the captured wall (composite) or blended by Qt over the live wall (overlay)
// Nothing re-renders unless `source` changes (scene-graph dirty propagation); live:false freezes
// the capture until refresh(). enabled:false unloads the whole chain (textures freed, zero cost).
Item {
    id: root

    property Item source: null
    property bool live: true

    // SE Natural Bloom parameters (same ranges/meaning as the Unity component)
    property real intensity: 0.22           // SE bloomIntensity; lerp factor = exp(x) - 1
    property real scatter: 0.35             // SE bloomScatterFactor 0..1; exponent = x*5 - 2.5
    property real lensDirtIntensity: 0.2    // SE lensDirtIntensity; factor = exp(x) - 1
    property real lensDirtScatter: 0.5      // SE lensDirtScatterFactor 0..1
    // pseudo-HDR: LDR heat v -> gain 1 + hdrBoost * v^hdrPower (orange/amber/bone >> graphite)
    property real hdrBoost: 8.0
    property real hdrPower: 6.0
    property real halation: 0.2             // carmine film halation on the wide octaves (0 = off)

    property bool composite: true
    property real captureScale: 0.5         // overlay mode only: capture res vs device res (<= 0.5)
    property real devicePixelRatio: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1
    property url lensDirtTexture: Qt.resolvedUrl("lens-dirt.png")
    property int hdrFormat: ShaderEffectSource.RGBA16F

    // re-capture once (use with live: false)
    function refresh() {
        if (chain.item)
            chain.item.capture.scheduleUpdate();
    }

    readonly property int pw: Math.max(1, Math.round(width * devicePixelRatio))
    readonly property int ph: Math.max(1, Math.round(height * devicePixelRatio))

    function _w(i, s) { return Math.pow(i + 1, s * 5.0 - 2.5); }
    // SE octave weights for levels 1..6 (SE octaves 1..6 at 1/4..1/128 res), normalized
    function _weights(s) {
        let w = [], t = 0;
        for (let i = 1; i <= 6; i++) { const v = _w(i, s); w.push(v); t += v; }
        return w.map(v => v / t);
    }
    readonly property var _wb: _weights(scatter)
    readonly property var _wl: _weights(lensDirtScatter)
    function _h(level) { return level >= 3 ? halation * 0.25 : 0.0; }

    // level 0 = capture, level 1 = 1/4 device res, then halving
    function _sz(level) {
        if (level === 0)
            return composite ? Qt.size(pw, ph)
                             : Qt.size(Math.max(1, Math.round(pw * captureScale)), Math.max(1, Math.round(ph * captureScale)));
        let w = Math.max(1, Math.ceil(pw / 4)), h = Math.max(1, Math.ceil(ph / 4));
        for (let i = 1; i < level; i++) { w = Math.max(1, Math.ceil(w / 2)); h = Math.max(1, Math.ceil(h / 2)); }
        return Qt.size(w, h);
    }

    component Down: Item {
        id: st
        property var input
        property size inSize
        property size outSize
        property bool pre: false
        readonly property alias tex: ses
        ShaderEffect {
            id: fx
            width: st.outSize.width; height: st.outSize.height
            property var src: st.input
            property vector2d texel: Qt.vector2d(1 / st.inSize.width, 1 / st.inSize.height)
            property real hdrBoost: root.hdrBoost
            property real hdrPower: root.hdrPower
            blending: false
            fragmentShader: st.pre ? Qt.resolvedUrl("shaders/prefilter.frag.qsb") : Qt.resolvedUrl("shaders/down.frag.qsb")
        }
        ShaderEffectSource {
            id: ses
            sourceItem: fx; hideSource: true; visible: false
            textureSize: st.outSize; format: root.hdrFormat; smooth: true
        }
    }

    component Up: Item {
        id: st
        property var coarseTex
        property size coarseSize
        property var curTex
        property size outSize
        property vector4d sw: Qt.vector4d(1, 1, 0, 0)
        property vector4d dw
        readonly property alias tex: ses
        ShaderEffect {
            id: fx
            width: st.outSize.width; height: st.outSize.height
            property var coarse: st.coarseTex
            property var cur: st.curTex
            property vector2d texel: Qt.vector2d(1 / st.coarseSize.width, 1 / st.coarseSize.height)
            property vector4d sScale: st.sw
            property vector4d dScale: st.dw
            blending: false
            fragmentShader: Qt.resolvedUrl("shaders/up.frag.qsb")
        }
        ShaderEffectSource {
            id: ses
            sourceItem: fx; hideSource: true; visible: false
            textureSize: st.outSize; format: root.hdrFormat; smooth: true
        }
    }

    Loader {
        id: chain
        anchors.fill: parent
        active: root.enabled && root.visible && root.source !== null
        sourceComponent: Item {
            property alias capture: cap
            ShaderEffectSource {
                id: cap
                sourceItem: root.source
                live: root.live
                hideSource: root.composite
                visible: false
                textureSize: root._sz(0)
                format: ShaderEffectSource.RGBA8
                smooth: true
            }
            Down { id: d1; pre: true; input: cap; inSize: root._sz(0); outSize: root._sz(1) }
            Down { id: d2; input: d1.tex; inSize: root._sz(1); outSize: root._sz(2) }
            Down { id: d3; input: d2.tex; inSize: root._sz(2); outSize: root._sz(3) }
            Down { id: d4; input: d3.tex; inSize: root._sz(3); outSize: root._sz(4) }
            Down { id: d5; input: d4.tex; inSize: root._sz(4); outSize: root._sz(5) }
            Down { id: d6; input: d5.tex; inSize: root._sz(5); outSize: root._sz(6) }
            Up {
                id: u5; coarseTex: d6.tex; coarseSize: root._sz(6); curTex: d5.tex; outSize: root._sz(5)
                sw: Qt.vector4d(root._wb[5], root._wl[5], root._h(6), 0)
                dw: Qt.vector4d(root._wb[4], root._wl[4], root._h(5), 0)
            }
            Up { id: u4; coarseTex: u5.tex; coarseSize: root._sz(5); curTex: d4.tex; outSize: root._sz(4)
                 dw: Qt.vector4d(root._wb[3], root._wl[3], root._h(4), 0) }
            Up { id: u3; coarseTex: u4.tex; coarseSize: root._sz(4); curTex: d3.tex; outSize: root._sz(3)
                 dw: Qt.vector4d(root._wb[2], root._wl[2], root._h(3), 0) }
            Up { id: u2; coarseTex: u3.tex; coarseSize: root._sz(3); curTex: d2.tex; outSize: root._sz(2)
                 dw: Qt.vector4d(root._wb[1], root._wl[1], root._h(2), 0) }
            Up { id: u1; coarseTex: u2.tex; coarseSize: root._sz(2); curTex: d1.tex; outSize: root._sz(1)
                 dw: Qt.vector4d(root._wb[0], root._wl[0], root._h(1), 0) }

            Image {
                id: lensImg
                visible: false
                source: root.lensDirtTexture
                sourceSize: Qt.size(1280, 800)
                smooth: true
            }
            ShaderEffect {
                anchors.fill: parent
                property var bloom: u1.tex
                property var lens: lensImg
                property var src: cap
                property vector2d texel: Qt.vector2d(1 / root._sz(1).width, 1 / root._sz(1).height)
                property real k: Math.exp(root.intensity) - 1
                property real kL: Math.exp(root.lensDirtIntensity) - 1
                fragmentShader: root.composite ? Qt.resolvedUrl("shaders/composite.frag.qsb")
                                               : Qt.resolvedUrl("shaders/glow.frag.qsb")
            }
        }
    }
}
