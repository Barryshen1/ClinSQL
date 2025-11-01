WITH filtered_admissions AS (
  SELECT 
    a.subject_id, 
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND DATE_DIFF(a.admittime, 
                  DATETIME(p.anchor_year - p.anchor_age, 1, 1, 0, 0, 0), 
                  YEAR) BETWEEN 75 AND 85
),
procedure_counts AS (
  SELECT 
    fa.hadm_id,
    COUNT(DISTINCT 
      CASE WHEN dicd.icd_code IS NOT NULL 
        THEN CONCAT(proc.icd_code, '_', proc.icd_version) 
      END
    ) AS num_distinct_procedures
  FROM filtered_admissions fa
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON fa.hadm_id = proc.hadm_id 
    AND fa.subject_id = proc.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dicd
    ON proc.icd_code = dicd.icd_code 
    AND proc.icd_version = dicd.icd_version
    AND REGEXP_CONTAINS(
          dicd.long_title, 
          r'(?i)ECG|EKG|electrocardiogram|telemetry|cardiac monitoring'
        )
  GROUP BY fa.hadm_id
)
SELECT 
  APPROX_QUANTILES(num_distinct_procedures, 100)[OFFSET(75)] 
    AS percentile_75_distinct_procedures
FROM procedure_counts;