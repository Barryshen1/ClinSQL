WITH admissions_with_age AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 58 AND 68
),
primary_diagnosis AS (
  SELECT
    d.hadm_id,
    diag.long_title
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
    ON d.icd_code = diag.icd_code AND d.icd_version = diag.icd_version
  WHERE d.seq_num = 1
),
chest_pain_ami AS (
  SELECT hadm_id
  FROM primary_diagnosis
  WHERE 
    LOWER(long_title) LIKE '%chest pain%'
    OR (LOWER(long_title) LIKE '%myocardial infarction%' AND LOWER(long_title) LIKE '%acute%')
),
troponin_t_initial AS (
  SELECT 
    hadm_id,
    valuenum
  FROM (
    SELECT 
      l.hadm_id,
      l.charttime,
      l.valuenum,
      ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime, l.labevent_id) as rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d
      ON l.itemid = d.itemid
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON l.hadm_id = a.hadm_id
    WHERE LOWER(d.label) LIKE '%troponin t%'
      AND l.valueuom = 'ng/mL'
      AND l.valuenum IS NOT NULL
      AND l.charttime >= a.admittime
  ) t
  WHERE rn = 1
    AND valuenum > 0.04
)
SELECT 
  COUNT(*) AS total_patients,
  SUM(a.hospital_expire_flag) AS deaths,
  AVG(a.hospital_expire_flag) AS mortality_rate
FROM admissions_with_age a
JOIN chest_pain_ami cpa ON a.hadm_id = cpa.hadm_id
JOIN troponin_t_initial tti ON a.hadm_id = tti.hadm_id;