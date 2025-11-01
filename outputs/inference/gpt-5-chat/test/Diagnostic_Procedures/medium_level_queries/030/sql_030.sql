WITH cohort AS (
  SELECT DISTINCT
    adm.subject_id,
    adm.hadm_id,
    p.gender,
    p.anchor_age,
    adm.admittime,
    adm.dischtime,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON adm.hadm_id = dx.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddx
    ON dx.icd_code = ddx.icd_code
    AND dx.icd_version = ddx.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
    AND DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 8
    -- crude text filter for upper GI bleed
    AND (
      UPPER(ddx.long_title) LIKE '%UPPER%GASTROINTESTINAL%HEMORRH%'
      OR UPPER(ddx.long_title) LIKE '%GASTRIC%ULCER%HEMORRH%'
      OR UPPER(ddx.long_title) LIKE '%DUODENAL%ULCER%HEMORRH%'
      OR UPPER(ddx.long_title) LIKE '%GASTRODUODENAL%HEMORRH%'
    )
),
proc_counts AS (
  SELECT
    c.hadm_id,
    c.los_days,
    CASE
      WHEN c.los_days BETWEEN 1 AND 4 THEN '1-4_days'
      WHEN c.los_days BETWEEN 5 AND 8 THEN '5-8_days'
    END AS los_category,
    COUNT(*) AS num_diag_procs
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON c.hadm_id = pr.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dpr
    ON pr.icd_code = dpr.icd_code
    AND pr.icd_version = dpr.icd_version
  WHERE LOWER(dpr.long_title) LIKE '%diagnostic%'
  GROUP BY c.hadm_id, c.los_days
)
SELECT
  los_category,
  q[OFFSET(1)] AS p25, -- 0= min, 1=25%, 2=median, 3=75%, 4= max
  q[OFFSET(2)] AS p50,
  q[OFFSET(3)] AS p75
FROM (
  SELECT
    los_category,
    APPROX_QUANTILES(num_diag_procs, 4) AS q
  FROM proc_counts
  GROUP BY los_category
)
ORDER BY los_category;