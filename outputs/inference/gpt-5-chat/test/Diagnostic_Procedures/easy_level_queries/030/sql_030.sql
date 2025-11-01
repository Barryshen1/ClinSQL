WITH echo_counts AS (
  SELECT
    pr.hadm_id,
    COUNT(DISTINCT pr.icd_code) AS distinct_echo_procs
  FROM `physionet-data.mimiciv_3_1_hosp.patients` pat
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON pat.subject_id = adm.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON adm.hadm_id = pr.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dpr
    ON pr.icd_code = dpr.icd_code
    AND pr.icd_version = dpr.icd_version
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 84 AND 94
    AND LOWER(dpr.long_title) LIKE '%echocardiography%'
  GROUP BY pr.hadm_id
)
SELECT
  APPROX_QUANTILES(distinct_echo_procs, 100)[OFFSET(25)] AS p25_approx
FROM echo_counts;