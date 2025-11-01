WITH hf_male_66 AS (
  SELECT DISTINCT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON adm.subject_id = dx.subject_id
   AND adm.hadm_id = dx.hadm_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age = 66
    AND (
         (dx.icd_version = 9 AND dx.icd_code LIKE '428%')
         OR
         (dx.icd_version = 10 AND dx.icd_code LIKE 'I50%')
        )
),
creatinine_ids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE UPPER(label) = 'CREATININE'
    AND UPPER(fluid) = 'BLOOD'
)
SELECT
  c.subject_id,
  c.hadm_id,
  MAX(le.valuenum) AS max_creatinine_first24h
FROM hf_male_66 c
JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
  ON c.subject_id = le.subject_id
 AND c.hadm_id = le.hadm_id
JOIN creatinine_ids di
  ON le.itemid = di.itemid
WHERE le.valuenum IS NOT NULL
  AND le.charttime >= c.admittime
  AND le.charttime < c.admittime + INTERVAL 24 HOUR
GROUP BY c.subject_id, c.hadm_id
ORDER BY max_creatinine_first24h DESC;