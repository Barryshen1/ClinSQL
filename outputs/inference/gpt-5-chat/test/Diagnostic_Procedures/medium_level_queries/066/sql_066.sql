WITH asthma_females AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.subject_id = diag.subject_id
    AND adm.hadm_id    = diag.hadm_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 88 AND 98
    AND (
      (diag.icd_version = 9 AND diag.icd_code LIKE '493%') -- ICD-9 asthma
      OR (diag.icd_version = 10 AND diag.icd_code LIKE 'J45%') -- ICD-10 asthma
    )
),
diag_proc_counts AS (
  SELECT af.hadm_id,
         af.los_days,
         CASE 
            WHEN af.los_days BETWEEN 1 AND 3 THEN '1-3 days'
            WHEN af.los_days BETWEEN 4 AND 7 THEN '4-7 days'
         END AS los_group,
         COUNT(p.icd_code) AS num_diag_procs
  FROM asthma_females af
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    ON af.subject_id = p.subject_id
    AND af.hadm_id   = p.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON p.icd_code = dp.icd_code
    AND p.icd_version = dp.icd_version
  WHERE af.los_days BETWEEN 1 AND 7
    AND (dp.long_title LIKE '%diagnostic%' OR dp.long_title IS NULL)
  GROUP BY af.hadm_id, af.los_days, los_group
),
percentiles AS (
  SELECT
    los_group,
    APPROX_QUANTILES(num_diag_procs, 4) AS quantiles
  FROM diag_proc_counts
  WHERE los_group IS NOT NULL
  GROUP BY los_group
)
SELECT
  los_group,
  quantiles[OFFSET(1)] AS p25,
  quantiles[OFFSET(2)] AS p50,
  quantiles[OFFSET(3)] AS p75
FROM percentiles
ORDER BY los_group;