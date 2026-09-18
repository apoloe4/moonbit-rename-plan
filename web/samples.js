export const samples={
  "swap": {
    "policy": "exact",
    "entries": [
      {
        "name": "left.txt",
        "identity": "A"
      },
      {
        "name": "right.txt",
        "identity": "B"
      }
    ],
    "mappings": [
      {
        "source": "left.txt",
        "target": "right.txt"
      },
      {
        "source": "right.txt",
        "target": "left.txt"
      }
    ]
  },
  "cycle": {
    "policy": "exact",
    "entries": [
      {
        "name": "a.txt",
        "identity": "A"
      },
      {
        "name": "b.txt",
        "identity": "B"
      },
      {
        "name": "c.txt",
        "identity": "C"
      },
      {
        "name": "keep.txt",
        "identity": "K"
      }
    ],
    "mappings": [
      {
        "source": "a.txt",
        "target": "b.txt"
      },
      {
        "source": "b.txt",
        "target": "c.txt"
      },
      {
        "source": "c.txt",
        "target": "a.txt"
      }
    ],
    "verify": true
  },
  "blocked": {
    "policy": "ascii-fold",
    "entries": [
      {
        "name": "photo.jpg",
        "identity": "A"
      },
      {
        "name": "ARCHIVE.jpg",
        "identity": "B"
      }
    ],
    "mappings": [
      {
        "source": "photo.jpg",
        "target": "archive.jpg"
      }
    ]
  },
  "case_only": {
    "policy": "ascii-fold",
    "entries": [
      {
        "name": "Photo.JPG",
        "identity": "A"
      }
    ],
    "mappings": [
      {
        "source": "Photo.JPG",
        "target": "photo.jpg"
      }
    ]
  },
  "ambiguous": {
    "policy": "exact",
    "entries": [
      {
        "name": "left.txt",
        "identity": "same-content"
      },
      {
        "name": "right.txt",
        "identity": "same-content"
      }
    ],
    "mappings": [
      {
        "source": "left.txt",
        "target": "right.txt"
      },
      {
        "source": "right.txt",
        "target": "left.txt"
      }
    ]
  },
  "rule": {
    "policy": "ascii-fold",
    "entries": [
      {
        "name": "IMG_002.JPG",
        "identity": "image2"
      },
      {
        "name": "IMG_001.JPG",
        "identity": "image1"
      },
      {
        "name": "notes.txt",
        "identity": "note"
      }
    ],
    "rule": {
      "prefix": "trip-",
      "find": "IMG_",
      "replacement": "",
      "sequenceStart": 1,
      "sequenceWidth": 2,
      "onlySuffix": ".JPG",
      "caseMode": "lower"
    }
  }
};
