WITH hemorrhage_primary AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    COALESCE(a.dischtime, a.deathtime) AS endtime,
    (CASE
       WHEN p.anchor_age IS NOT NULL AND p.anchor_year IS NOT NULL THEN
         p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)
       ELSE NULL
     END) AS age_at_adm,
    UPPER(p.gender) AS gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE di.seq_num = 1
    -- primary diagnosis hemorrhagic stroke terms
    AND (dd.long_title LIKE '%hemorrhage%'
         OR dd.long_title LIKE '%intracranial hemorrhage%'
         OR dd.long_title LIKE '%subarachnoid hemorrhage%')
)
SELECT STDDEV_POP(los_days) AS los_sd_days
FROM (
  SELECT
    hadm_id,
    TIMESTAMP_DIFF(endtime, admittime, SECOND) / 86400.0 AS los_days
  FROM hemorrhage_primary
  WHERE endtime IS NOT NULL
    AND gender = 'MALE'
    AND age_at_adm BETWEEN 43 AND 53
    AND TIMESTAMP_DIFF(endtime, admittime, SECOND) > 0
) t;