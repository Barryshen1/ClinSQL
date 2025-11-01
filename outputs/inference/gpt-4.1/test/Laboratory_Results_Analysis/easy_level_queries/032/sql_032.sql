WITH copd_patients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE p.anchor_age = 90
    AND p.gender = 'M'
    AND (
      -- ICD-10 J44.x (COPD) or ICD-9 496
      (d.icd_version = 10 AND dd.icd_code LIKE 'J44%')
      OR (d.icd_version = 9 AND dd.icd_code = '496')
    )
),
creatinine_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%creatinine%'
    AND LOWER(fluid) = 'serum'
),
copd_icu_stays AS (
  SELECT icu.subject_id, icu.hadm_id, icu.stay_id, icu.intime, icu.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  WHERE icu.subject_id IN (SELECT subject_id FROM copd_patients)
),
creatinine_first24h AS (
  SELECT
    s.stay_id,
    AVG(l.valuenum) AS avg_creatinine
  FROM copd_icu_stays s
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON s.subject_id = l.subject_id
    AND s.hadm_id = l.hadm_id
    AND l.valuenum IS NOT NULL
    AND l.charttime >= s.intime
    AND l.charttime < TIMESTAMP_ADD(s.intime, INTERVAL 24 HOUR)
  JOIN creatinine_itemids ci
    ON l.itemid = ci.itemid
  GROUP BY s.stay_id
)
SELECT
  STDDEV(avg_creatinine) AS stddev_avg_creatinine_first24h
FROM creatinine_first24h
WHERE avg_creatinine IS NOT NULL;