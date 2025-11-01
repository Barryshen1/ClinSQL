WITH cohort AS (
  SELECT 
    adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 63 AND 73
),

cardiac_procedures_per_admission AS (
  SELECT 
    adm.hadm_id,
    COUNT(DISTINCT CASE WHEN dip.long_title LIKE '%cardiac%' THEN picd.icd_code END) AS cardiac_proc_count
  FROM cohort adm
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` picd
    ON adm.hadm_id = picd.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip
    ON picd.icd_code = dip.icd_code AND picd.icd_version = dip.icd_version
  GROUP BY adm.hadm_id
)

SELECT 
  APPROX_QUANTILES(cardiac_proc_count, 100)[OFFSET(75)] AS percentile_75
FROM cardiac_procedures_per_admission;