WITH target_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 78 AND 88
),
pacemaker_procedures AS (
  SELECT p.subject_id,
         p.hadm_id,
         p.icd_code,
         p.icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code
    AND p.icd_version = d.icd_version
  WHERE REGEXP_CONTAINS(LOWER(d.long_title), r'insertion of (permanent )?(cardiac )?(pacemaker|cardioverter-defibrillator|icd)')
),
procedure_counts AS (
  SELECT tp.subject_id,
         COUNT(DISTINCT CONCAT(pp.icd_code, '-', CAST(pp.hadm_id AS STRING))) AS proc_count
  FROM target_patients tp
  LEFT JOIN pacemaker_procedures pp
    ON tp.subject_id = pp.subject_id
  GROUP BY tp.subject_id
)
SELECT APPROX_QUANTILES(proc_count, 100)[OFFSET(25)] AS percentile_25
FROM procedure_counts;