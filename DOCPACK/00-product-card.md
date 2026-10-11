---
title: solo-notifications — Product Card
doc_id: CARD-solo-notifications
doc_type: product-card
verdict: showcase
version: 0.1
date: 2026-10-11
status: ร่างเพื่อพิจารณา
owner: Product owner (Book Dev)
---

# solo-notifications — Product Card

## 1. สรุปคุณค่าในหนึ่งประโยค

ช่วยเจ้าของ Solo Empire ไม่พลาดงานที่เลยกำหนด ใกล้ครบกำหนด หรือค้าง โดยเก็บกฎและบันทึกการแจ้งเตือนไว้ใน API/ฐานข้อมูลของ cell เอง และส่งสรุปทาง Telegram นอกช่วงเวลาพัก

## 2. ปัญหาและผู้ใช้เป้าหมาย

- ปัญหา: การแจ้งเตือนงานเคยอยู่ใน control plane ส่วนกลางของ solo-empire (SQLite) ทำให้แยก deploy และสิทธิ์ไม่ได้
- ผู้ใช้: เจ้าของ Solo Empire คนเดียว (internal) ไม่มีผู้ใช้ภายนอก

## 3. สิ่งที่ทำได้จริงตอนนี้

- API `/v1/notification-rules` และ `/v1/notifications` (คิว, ดู log, stats, บันทึกผลการส่ง) พร้อม `dedupe_key` กันซ้ำ ตาม `src/solo_notifications/app.py`
- ตัวส่ง `notifications-dispatch` ประเมินกฎ overdue / due_soon / high_priority / stale / blocked / reminder กับ tasks cell แล้วส่ง digest ทาง Telegram นอกช่วง 22:00-07:00 เวลา Asia/Bangkok (ตาม README และ `dispatch.py`)
- Permission `notifications.rule:*` และ `notifications.notification:*` ผ่าน token จาก `empire-platform`

## 4. หลักฐานสถานะ

| รายการ | ค่า (ตรวจจาก repository) |
|---|---|
| Stack | Python (FastAPI) |
| Commits | 4 (แรก 2026-10-10 → ล่าสุด 2026-10-11) |
| Source | ประมาณ 1,997 บรรทัดใน 11 ไฟล์ (ไม่รวมเทสต์) |
| Tests | 4 ไฟล์ |
| CI | ไม่มี |
| Deploy config | Dockerfile; Railway project `solo-notifications` (API + cron dispatcher `*/30 * * * *`) ตาม README; ไม่ได้ตรวจ deploy จริงในรอบนี้ |
| Live URL | ไม่มี (ไม่ได้ตรวจ) |
| README | 59 บรรทัด |

## 5. คุณค่าและจุดต่าง

- เป็น cell ที่เขียนเอง (ไม่ได้สร้างจาก `cell.yaml`) เพราะมีตัวส่งในตัว และไม่ publish graph events
- มุมรายได้: ไม่มี — ใช้ภายในเท่านั้น **[สมมติฐาน]** ว่า pattern rule + dedupe + digest ใช้ซ้ำกับผลิตภัณฑ์อื่นได้

## 6. ช่องว่างสำคัญ

- ไม่มี CI; ไม่มีเอกสารสถาปัตยกรรมนอก README
- ต้องมี `empire-platform` ออนไลน์และ tasks cell เพื่อทำงาน — ผูกกับ cell อื่นหลายตัว
- Telegram: บันทึกความจำระบุว่า token เดิมถูก revoke; ช่องทางส่งปัจจุบัน **[ต้องยืนยัน]**

## 7. คำตัดสิน

**`showcase`** — ระบบจริงที่ใช้ภายในและมีเทสต์ แต่ไม่ใช่ธุรกิจ เหมาะเป็นหลักฐานงาน backend แบบ cell; จะเปลี่ยนเป็น `invest` ถ้าจะแยกเป็นผลิตภัณฑ์แจ้งเตือนสำหรับผู้ใช้อื่น

## 8. ขั้นต่อไป

1. ยืนยันช่องทางส่งจริงหลัง revoke Telegram token และผล dispatcher ล่าสุด
2. เพิ่ม CI รัน `pytest`

## การอนุมัติ

| บทบาท | สถานะ | วันที่ | ลงนาม |
|---|---|---|---|
| Product owner (Book Dev) | รอพิจารณา | — | ________ |

## แหล่งข้อมูล

- `README.md`
- `src/solo_notifications/{app,dispatch,db}.py`
- `tests/`, `migrations/`, `Dockerfile`
