        }

        public static func == (lhs: KeyLocation, rhs: KeyLocation) -> Bool {
            lhs.key == rhs.key
                && lhs.center == rhs.center
                && lhs.utf8Bytes.0 == rhs.utf8Bytes.0
                && lhs.utf8Bytes.1 == rhs.utf8Bytes.1
                && lhs.utf8Bytes.2 == rhs.utf8Bytes.2
                && lhs.utf8Bytes.3 == rhs.utf8Bytes.3
                && lhs.utf8Length == rhs.utf8Length
        }
