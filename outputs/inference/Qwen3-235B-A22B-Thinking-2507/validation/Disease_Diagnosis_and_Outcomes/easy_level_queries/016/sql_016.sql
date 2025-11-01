WITH filtered_admissions AS (
  SELECT 
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / (24*60*60) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND a.dischtime IS NOT NULL
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 68 AND 78
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1
      WHERE d1.hadm_id = a.hadm_id
        AND (
          (d1.icd_version = 9 AND d1.icd_code IN ('480','481','482','483','484','485','486','4870'))
          OR 
          (d1.icd_version = 10 AND SUBSTR(d1.icd_code, 1, 3) IN ('J09','J10','J11','J12','J13','J14','J15','J16','J17','J18'))
        )
    )
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
      WHERE d2.hadm_id = a.hadm_id
        AND (
          (d2.icd_version = 9 AND d2.icd_code IN ('490','491','492','494','496'))
          OR 
          (d2.icd_version = 10 AND SUBSTR(d2.icd_code, 1, 3) IN ('J40','J41','J42','J43','J44','J47'))
        )
    )
)
SELECT 
  APPROX_QUANTILES(los_days, 1000)[OFFSET(750)] AS los_75th_percentile
FROM filtered_admissions;