"""Explicit-run regression: actual embedded C on independent OpenCV markers.
No OpenCV detector is used as the implementation under test.
"""
import ctypes as ct
import pathlib
import sys
import cv2
import numpy as np

ROOT = pathlib.Path(__file__).resolve().parents[2]
dll = ct.CDLL(str(ROOT / 'tmp/aruco/aruco_host.dll'))
dll.ua_test_detect.argtypes = [ct.POINTER(ct.c_ubyte), ct.c_uint, ct.c_uint,
                               ct.POINTER(ct.c_float), ct.POINTER(ct.c_uint)]
dll.ua_test_detect.restype = ct.c_int
dll.ua_test_workspace_size.restype = ct.c_uint
dictionary = cv2.aruco.getPredefinedDictionary(cv2.aruco.DICT_4X4_50)

def detect(im):
    im = np.ascontiguousarray(im, dtype=np.uint8)
    corners = (ct.c_float * 8)()
    steps = ct.c_uint()
    value = dll.ua_test_detect(im.ctypes.data_as(ct.POINTER(ct.c_ubyte)),
                               im.shape[1], im.shape[0], corners, ct.byref(steps))
    assert steps.value < 1500, steps.value
    return value, np.array(corners).reshape(4, 2)

def render(marker_id, corners, low=15, high=235, seed=0):
    marker = cv2.aruco.generateImageMarker(dictionary, marker_id, 120)
    matrix = cv2.getPerspectiveTransform(np.float32([[0,0],[119,0],[119,119],[0,119]]),
                                        np.float32(corners))
    im = cv2.warpPerspective(marker, matrix, (160,90), flags=cv2.INTER_NEAREST,
                             borderValue=255)
    im = low + im.astype(np.float32) * ((high-low)/255)
    if seed:
        im += np.random.default_rng(seed).normal(0, 2, im.shape)
    return np.clip(im,0,255).astype(np.uint8)

cases = 0
if '--rtl-output' in sys.argv:
    pixels=np.array([int(s,16) for s in (ROOT/'tmp/aruco/link_output.hex').read_text().split()],np.uint8)
    assert pixels.size==14400, pixels.size
    expected=np.array([int(s,16) for s in (ROOT/'tmp/aruco/link_input.hex').read_text().split()],np.uint8)
    assert np.array_equal(pixels,expected), 'RTL snapshot changed gray values'
    value,corners=detect(pixels.reshape(90,160))
    assert value==23,(value,corners)
    print('ARUCO_RTL_TO_C_IMAGE_PASS id=23 pixels=14400 not_board_signoff')
    sys.exit(0)
base = np.float32([[45,16],[100,16],[100,71],[45,71]])
for marker_id in range(50):
    for rotation in range(4):
        expected = np.roll(base, -rotation, axis=0)
        value, corners = detect(render(marker_id, expected))
        assert value == marker_id, (marker_id, rotation, value)
        assert np.max(np.linalg.norm(corners-expected, axis=1)) <= 3, (corners,expected)
        cases += 1
for angle in (17, 32, 45, 67):
    a = np.deg2rad(angle)
    rotation = np.float32([[np.cos(a),-np.sin(a)],[np.sin(a),np.cos(a)]])
    q = (base-np.float32([72.5,43.5])) @ rotation.T + np.float32([80,45])
    for marker_id in (0,7,23,49):
        value, corners = detect(render(marker_id,q,low=18,high=80,seed=marker_id+1))
        assert value == marker_id, ('dim rotate', angle,marker_id,value)
        assert np.max(np.linalg.norm(corners-q,axis=1)) < 5, (angle,corners,q)
        cases += 1
for q in ([[42,14],[112,24],[99,75],[52,65]], [[52,9],[108,18],[116,76],[34,68]]):
    for marker_id in (0,7,23,49):
        value, corners = detect(render(marker_id,q))
        assert value == marker_id, ('perspective',marker_id,value)
        cases += 1
for im in (np.zeros((90,160),np.uint8), np.full((90,160),255,np.uint8),
           np.full((90,160),60,np.uint8),
           np.random.default_rng(19).integers(0,256,(90,160),dtype=np.uint8)):
    assert detect(im)[0] == -1
    cases += 1
for seed in range(40):
    im=np.random.default_rng(seed).integers(0,256,(90,160),dtype=np.uint8)
    assert detect(im)[0]==-1, ('negative noise',seed)
    cases+=1
for q in ([[-12,14],[40,14],[40,69],[-12,69]],
          [[50,25],[59,25],[59,34],[50,34]]):
    assert detect(render(23,q))[0]==-1, 'cropped or undersized marker accepted'
    cases+=1
print(f'ARUCO_IMAGE_C_PASS cases={cases} workspace={dll.ua_test_workspace_size()} '
      'synthetic_only_not_hardware_signoff')
fixture=render(23,[[42,14],[112,24],[99,75],[52,65]],low=18,high=80,seed=17)
(ROOT/'tmp/aruco/link_input.hex').write_text('\n'.join(f'{p:02x}' for p in fixture.flat)+'\n')
