WITH patients_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.hospital_expire_flag,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_year IS NOT NULL
    AND p.anchor_age IS NOT NULL
    AND a.admittime IS NOT NULL
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 64 AND 74
),
chest_pain_admissions AS (
  SELECT DISTINCT
    d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE
    (d.icd_version = 9 AND d.icd_code = '786.5') OR
    (d.icd_version = 10 AND d.icd_code = 'R07.9')
),
troponin_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE label LIKE '%hs-Troponin T%'
),
troponin_events AS (
  SELECT
    l.hadm_id,
    l.charttime,
    l.valuenum,
    l.ref_range_upper,
    ROW_NUMBER() OVER (
      PARTITION BY l.hadm_id
      ORDER BY l.charttime
    ) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN troponin_items t ON l.itemid = t.itemid
  WHERE
    l.valuenum IS NOT NULL
    AND l.ref_range_upper IS NOT NULL
    AND l.valuenum > l.ref_range_upper
),
eligible_admissions AS (
  SELECT
    pa.*
  FROM patients_admissions pa
  JOIN chest_pain_admissions cpa
    ON pa.hadm_id = cpa.hadm_id
),
first_troponin AS (
  SELECT
    e.hadm_id
  FROM troponin_events e
  WHERE e.rn = 1
)
SELECT
  COUNT(*) AS total_admissions,
  AVG(age_at_admission) AS avg_age,
  MIN(age_at_admission) AS min_age,
  MAX(age_at_admission) AS max_age,
  SUM(CAST(hospital_expire_flag AS INT64)) AS deaths,
  SUM(CAST(hospital_expire_flag AS INT64)) / COUNT(*) AS mortality_rate
FROM eligible_admissions ea
JOIN first_troponin ft
  ON ea.hadm_id = ft.hadm_id;