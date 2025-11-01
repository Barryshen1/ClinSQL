WITH mcs_procedures AS (
  SELECT DISTINCT 
    p.subject_id,
    p.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code 
    AND CAST(p.icd_version AS STRING) = CAST(d.icd_version AS STRING)
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON p.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 56 AND 66
    AND CAST(p.icd_version AS STRING) = '10'
    AND (
      p.icd_code IN ('02.9', '39.65', '37.68')  -- Common MCS codes: assist devices, IABP, ECMO
      OR d.long_title LIKE '%Impella%'
      OR d.long_title LIKE '%ECMO%'
      OR d.long_title LIKE '%VAD%'
      OR d.long_title LIKE '%IABP%'
      OR d.long_title LIKE '%circulatory support%'
    )
),
patient_mcs_counts AS (
  SELECT 
    subject_id,
    COUNT(DISTINCT icd_code) AS distinct_mcs_count
  FROM mcs_procedures
  GROUP BY subject_id
)
SELECT 
  STDDEV(distinct_mcs_count) AS sd_distinct_mcs_procedures
FROM patient_mcs_counts;