WITH male_patients AS (
  SELECT subject_id, anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 83 AND 93
),
chestpain_ami_admissions AS (
  -- ICD-9: 410.x (AMI), 786.5x (chest pain)
  -- ICD-10: I21.x, I22.x (AMI), R07.x (chest pain)
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN male_patients p ON d.subject_id = p.subject_id
  WHERE (
    (d.icd_version = 9 AND (
      REGEXP_CONTAINS(d.icd_code, r'^410') OR
      REGEXP_CONTAINS(d.icd_code, r'^7865')
    ))
    OR
    (d.icd_version = 10 AND (
      REGEXP_CONTAINS(d.icd_code, r'^I21') OR
      REGEXP_CONTAINS(d.icd_code, r'^I22') OR
      REGEXP_CONTAINS(d.icd_code, r'^R07')
    ))
  )
),
troponin_labitems AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
),
initial_troponin AS (
  -- Get initial Troponin T for each admission
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum,
    l.valueuom,
    ROW_NUMBER() OVER (PARTITION BY l.subject_id, l.hadm_id ORDER BY l.charttime ASC) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN troponin_labitems t ON l.itemid = t.itemid
  WHERE l.valuenum IS NOT NULL
),
admissions_with_initial_troponin AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    i.charttime AS initial_trop_time,
    i.valuenum AS initial_troponin,
    i.valueuom,
    p.anchor_age,
    adm.admittime,
    adm.dischtime,
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, DAY) AS los
  FROM chestpain_ami_admissions a
  JOIN initial_troponin i
    ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id AND i.rn = 1
  JOIN male_patients p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON a.subject_id = adm.subject_id AND a.hadm_id = adm.hadm_id
  WHERE adm.dischtime IS NOT NULL
    -- Troponin T above 99th percentile (assume ng/mL > 0.01 or µg/L > 0.014)
    AND (
      (LOWER(i.valueuom) IN ('ng/ml', 'ng/ml.') AND i.valuenum > 0.01)
      OR
      (LOWER(i.valueuom) IN ('µg/l', 'ug/l', 'mcg/l') AND i.valuenum > 0.014)
    )
)
SELECT
  COUNT(*) AS N,
  ROUND(AVG(anchor_age), 2) AS mean_age,
  ROUND(AVG(los), 2) AS mean_los_days,
  ROUND(MIN(initial_troponin), 4) AS min_initial_troponin,
  ROUND(MAX(initial_troponin), 4) AS max_initial_troponin,
  ROUND(AVG(initial_troponin), 4) AS mean_initial_troponin,
  ROUND(APPROX_QUANTILES(initial_troponin, 2)[OFFSET(1)], 4) AS median_initial_troponin
FROM admissions_with_initial_troponin
;