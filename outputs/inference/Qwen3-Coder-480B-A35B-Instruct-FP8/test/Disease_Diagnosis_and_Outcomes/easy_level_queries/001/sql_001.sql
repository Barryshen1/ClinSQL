WITH admissions_with_both_conditions AS (
  SELECT hadm_id
  FROM (
    SELECT
      di.hadm_id,
      COUNT(*) AS dx_count
    FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
    JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d
      ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
    WHERE
      -- UGIB ICD codes
      (d.icd_version = 10 AND d.icd_code IN ('K25', 'K26', 'K27', 'K28', 'K922'))
      OR
      (d.icd_version = 9 AND d.icd_code IN ('531', '532', '533', '534'))
      OR
      -- COPD Exacerbation ICD codes
      (d.icd_version = 10 AND d.icd_code IN ('J441'))
      OR
      (d.icd_version = 9 AND d.icd_code IN ('49121', '49122'))
    GROUP BY di.hadm_id
    HAVING 
      COUNT(DISTINCT CASE
        WHEN (d.icd_version = 10 AND d.icd_code IN ('K25', 'K26', 'K27', 'K28', 'K922'))
          OR (d.icd_version = 9 AND d.icd_code IN ('531', '532', '533', '534'))
        THEN 1
        ELSE NULL
      END) > 0
      AND 
      COUNT(DISTINCT CASE
        WHEN (d.icd_version = 10 AND d.icd_code = 'J441')
          OR (d.icd_version = 9 AND d.icd_code IN ('49121', '49122'))
        THEN 1
        ELSE NULL
      END) > 0
  )
)

SELECT 
  AVG(DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0) AS avg_hospital_los
FROM admissions_with_both_conditions b
JOIN physionet-data.mimiciv_3_1_hosp.admissions a
  ON b.hadm_id = a.hadm_id
JOIN physionet-data.mimiciv_3_1_hosp.patients p
  ON a.subject_id = p.subject_id
WHERE 
  p.gender = 'M'
  AND p.anchor_age BETWEEN 86 AND 96;