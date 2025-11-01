WITH eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 41 AND 51
),
procedure_counts AS (
  SELECT
    ep.subject_id,
    COUNT(DISTINCT CONCAT(pi.icd_code, '-', pi.icd_version)) AS distinct_procedure_count
  FROM eligible_patients ep
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    ON ep.subject_id = pi.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip
    ON pi.icd_code = dip.icd_code
    AND pi.icd_version = dip.icd_version
    AND (dip.long_title LIKE '%ECG%' OR dip.long_title LIKE '%Telemetry%')
  GROUP BY ep.subject_id
)
SELECT
  APPROX_QUANTILES(distinct_procedure_count, 100)[OFFSET(75)] AS percentile_75
FROM procedure_counts;