WITH cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
    AND d.seq_num = 1  -- primary diagnosis
    AND d.icd_version = 10
    AND d.icd_code IN (
      'K922',  -- Gastrointestinal hemorrhage, unspecified
      'K250',  -- Acute gastric ulcer with hemorrhage
      'K260',  -- Acute duodenal ulcer with hemorrhage
      'K270',  -- Acute peptic ulcer, site unspecified, with hemorrhage
      'K280',  -- Acute gastrojejunal ulcer with hemorrhage
      'K290',  -- Acute gastritis with bleeding
      'K2211'  -- Esophageal hemorrhage
    )
)
SELECT
  PERCENTILE_CONT(los_days, 0.25) OVER() AS los_25th_percentile
FROM cohort
LIMIT 1;