WITH eligible_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    p.anchor_year,
    p.anchor_age,
    (p.anchor_year - p.anchor_age) AS birth_year,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
),
ischemic_stroke_admissions AS (
  SELECT DISTINCT
    ea.hadm_id,
    ea.subject_id,
    ea.admittime,
    ea.age_at_admission
  FROM eligible_admissions ea
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON ea.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%ischemic stroke%'
    AND ea.age_at_admission = 82
),
glucose_measurements AS (
  SELECT
    l.hadm_id,
    l.valuenum AS glucose_mg_dL,
    ROW_NUMBER() OVER (
      PARTITION BY l.hadm_id
      ORDER BY l.charttime
    ) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON l.itemid = dl.itemid
  WHERE LOWER(dl.label) LIKE '%glucose%'
    AND dl.category = 'Blood Glucose'
    AND l.valueuom = 'mg/dL'
),
first_glucose AS (
  SELECT
    g.hadm_id,
    g.glucose_mg_dL
  FROM glucose_measurements g
  WHERE g.rn = 1
)
SELECT
  APPROX_QUANTILES(glucose_mg_dL, 100)[OFFSET(75)] AS p75_glucose
FROM ischemic_stroke_admissions i
INNER JOIN first_glucose f
  ON i.hadm_id = f.hadm_id
WHERE f.glucose_mg_dL IS NOT NULL;