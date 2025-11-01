WITH female_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
),
pneumonia_admissions AS (
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN female_patients f ON d.subject_id = f.subject_id
  WHERE (
    -- ICD-10 pneumonia: J12-J18
    (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^J1[2-8]'))
    -- ICD-9 pneumonia: 480-486
    OR (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^48[0-6]'))
  )
),
creatinine_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%creatinine%'
    AND LOWER(fluid) = 'serum'
),
creatinine_24hr_avg AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    AVG(l.valuenum) AS avg_creatinine_24hr
  FROM pneumonia_admissions a
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON a.subject_id = adm.subject_id AND a.hadm_id = adm.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON a.subject_id = l.subject_id AND a.hadm_id = l.hadm_id
  JOIN creatinine_items ci
    ON l.itemid = ci.itemid
  WHERE l.valuenum IS NOT NULL
    AND l.charttime >= adm.admittime
    AND l.charttime < TIMESTAMP_ADD(adm.admittime, INTERVAL 24 HOUR)
  GROUP BY a.subject_id, a.hadm_id
)
SELECT MIN(avg_creatinine_24hr) AS min_24hr_avg_serum_creatinine
FROM creatinine_24hr_avg;