///|
async test "delivery member comparison checks exact EOF and 64 KiB boundaries then recovers" {
  let root = @fs.tmpdir(prefix="mtl-delivery-stream")
  defer @fs.rmdir(root)
  let path = root + "/member"
  defer @fs.remove(path)
  for size in [0, 1, 65535, 65536, 65537] {
    let bytes = Bytes::make(size, b'x')
    @fs.write_file(path, bytes)
    check_delivery_file(path, bytes)
    assert_true(
      (try check_delivery_file(path, Bytes::make(size + 1, b'x')) catch {
        _ => None
      } noraise {
        _ => Some(())
      })
      is None,
    )
    if size > 0 {
      assert_true(
        (try check_delivery_file(path, Bytes::make(size - 1, b'x')) catch {
          _ => None
        } noraise {
          _ => Some(())
        })
        is None,
      )
      assert_true(
        (try check_delivery_file(path, Bytes::make(size, b'y')) catch {
          _ => None
        } noraise {
          _ => Some(())
        })
        is None,
      )
    }
    check_delivery_file(path, bytes)
  }
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "delivery refuses symlink members and symlink roots" {
  let root = @fs.tmpdir(prefix="mtl-delivery-link")
  defer @fs.rmdir(root)
  let file = root + "/regular"
  @fs.write_file(file, b"source")
  defer @fs.remove(file)
  let link = root + "/link"
  @fs.symlink(target=file, link)
  defer @fs.remove(link)
  assert_true(
    (try check_delivery_file(link, b"source") catch {
      _ => None
    } noraise {
      _ => Some(())
    })
    is None,
  )
  let directory_link = root + "/directory"
  @fs.symlink(target=root, directory_link)
  defer @fs.remove(directory_link)
  assert_true(
    (try verify_delivery(directory_link) catch {
      _ => None
    } noraise {
      _ => Some(())
    })
    is None,
  )
  check_delivery_file(file, b"source")
}
