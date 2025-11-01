WITH filtered_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 41 AND 51
),
proc_counts AS (
  SELECT 
    p.subject_id, 
    COUNT(DISTINCT CASE 
      WHEN (LOWER(dip.long_title) LIKE '%ecg%' 
            OR LOWER(dip.long_title) LIKE '%electrocardiogram%' 
            OR LOWER(dip.long_title) LIKE '%telemetry%' 
            OR LOWER(dip.long_title) LIKE '%cardiac monitor%') 
      THEN pi.icd_code 
      END
    ) AS distinct_procs
  FROM filtered_patients p
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi 
    ON p.subject_id = pi.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip 
    ON pi.icd_code = dip.icd_code 
    AND pi.icd_version = dip.icd_version
  GROUP BY p.subject_id
)
SELECT APPROX_QUANTILES(distinct_procs, 5)[OFFSET(3)] AS p75
FROM proc_counts;