WITH asthma_female_88_98 AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di ON p.subject_id = di.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 88 AND 98
    AND LOWER(d.long_title) LIKE '%asthma%'
  GROUP BY p.subject_id
),
icu_stays_filtered AS (
  SELECT af.subject_id, adm.hadm_id, icu.stay_id, icu.los,
    CASE 
      WHEN icu.los >= 1 AND icu.los <= 3 THEN '1-3'
      WHEN icu.los >= 4 AND icu.los <= 7 THEN '4-7'
      ELSE NULL
    END AS stay_group
  FROM asthma_female_88_98 af
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions adm ON af.subject_id = adm.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays icu ON adm.hadm_id = icu.hadm_id
  WHERE icu.los IS NOT NULL
    AND icu.los >= 1
    AND icu.los <= 7
),
diagnostic_procs AS (
  SELECT 
    isf.hadm_id,
    isf.stay_group,
    COUNT(*) AS proc_count
  FROM icu_stays_filtered isf
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.procedureevents pe 
    ON isf.stay_id = pe.stay_id
  WHERE LOWER(pe.ordercategoryname) = 'diagnostic'
  GROUP BY isf.hadm_id, isf.stay_group
),
percentiles AS (
  SELECT
    stay_group,
    APPROX_QUANTILES(proc_count, 1000)[OFFSET(250)] AS pct_25,
    APPROX_QUANTILES(proc_count, 1000)[OFFSET(500)] AS pct_50,
    APPROX_QUANTILES(proc_count, 1000)[OFFSET(750)] AS pct_75
  FROM diagnostic_procs
  GROUP BY stay_group
)
SELECT * FROM percentiles
ORDER BY stay_group;