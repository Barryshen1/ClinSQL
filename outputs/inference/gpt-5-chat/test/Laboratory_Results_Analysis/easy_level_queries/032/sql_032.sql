WITH copd_admissions AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, p.gender, p.anchor_age, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id
   AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age = 90
    AND (
      (d.icd_version = 9 AND d.icd_code = '496')               -- ICD-9 COPD
      OR (d.icd_version = 10 AND d.icd_code LIKE 'J44%')        -- ICD-10 COPD
    )
),
creatinine_items AS (
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) = 'creatinine'
    AND LOWER(fluid) IN ('blood', 'serum')
),
creatinine_first24 AS (
  SELECT ca.subject_id, ca.hadm_id,
         AVG(le.valuenum) AS mean_creatinine
  FROM copd_admissions ca
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON ca.subject_id = le.subject_id
   AND ca.hadm_id = le.hadm_id
  JOIN creatinine_items ci
    ON le.itemid = ci.itemid
  WHERE le.valuenum IS NOT NULL
    AND le.charttime >= ca.admittime
    AND le.charttime < TIMESTAMP_ADD(ca.admittime, INTERVAL 24 HOUR)
  GROUP BY ca.subject_id, ca.hadm_id
)
SELECT STDDEV(mean_creatinine) AS stddev_creatinine_first24
FROM creatinine_first24;