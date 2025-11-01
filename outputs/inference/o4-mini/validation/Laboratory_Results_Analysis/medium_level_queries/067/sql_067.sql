WITH ami_admissions AS (
  SELECT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE
    d.seq_num = 1
    AND d.icd_version = 9
    AND d.icd_code LIKE '410%'
),
troponin_itemids AS (
  SELECT
    itemid
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE
    LOWER(label) LIKE '%troponin t%'
),
first_troponin AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.valuenum AS first_troponin,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN
    troponin_itemids ti
  ON
    le.itemid = ti.itemid
  WHERE
    le.valuenum IS NOT NULL
),
first_troponin_per_adm AS (
  SELECT
    ft.subject_id,
    ft.hadm_id,
    ft.first_troponin
  FROM
    first_troponin ft
  WHERE
    ft.rn = 1
    AND ft.first_troponin > 0.01
)
SELECT
  COUNT(DISTINCT a.subject_id) AS patient_count,
  COUNT(*) AS admission_count,
  AVG(p.anchor_age) AS mean_age,
  AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY)) AS mean_los_days,
  AVG(ft.first_troponin) AS mean_first_troponin,
  MIN(ft.first_troponin) AS min_first_troponin,
  MAX(ft.first_troponin) AS max_first_troponin,
  AVG(a.hospital_expire_flag) AS in_hospital_mortality_rate
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` p
ON
  a.subject_id = p.subject_id
JOIN
  ami_admissions ami
ON
  a.subject_id = ami.subject_id
  AND a.hadm_id = ami.hadm_id
JOIN
  first_troponin_per_adm ft
ON
  a.subject_id = ft.subject_id
  AND a.hadm_id = ft.hadm_id
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 52 AND 62;