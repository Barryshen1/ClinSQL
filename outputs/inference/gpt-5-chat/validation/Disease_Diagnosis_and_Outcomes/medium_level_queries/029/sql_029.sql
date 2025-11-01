WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING(subject_id)
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 57 AND 67
),
dx AS (
  SELECT
    hadm_id,
    MAX(CASE 
          WHEN ( (icd_version = 9 AND icd_code IN ('78552'))
                 OR (icd_version = 10 AND icd_code IN ('R6521')) )
          THEN 1 ELSE 0 
        END) AS shock_flag,
    MAX(CASE 
          WHEN (
                 (icd_version = 9 AND icd_code BETWEEN '0380' AND '0389')
                 OR (icd_version = 10 AND (icd_code LIKE 'A40%' OR icd_code LIKE 'A41%'))
               )
          THEN 1 ELSE 0
        END) AS sepsis_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
cohort_labeled AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    CASE 
      WHEN d.shock_flag = 1 THEN 'Septic shock'
      WHEN d.sepsis_flag = 1 THEN 'Sepsis without shock'
      ELSE NULL
    END AS sepsis_group,
    DATE_DIFF(c.dischtime, c.admittime, DAY) AS los_days,
    CASE WHEN DATE_DIFF(c.dischtime, c.admittime, DAY) <= 7 THEN '<=7' ELSE '>7' END AS los_cat,
    NULL AS charlson_comorbidity_index, -- placeholder since table not accessible
    NULL AS charlson_cat,
    c.hospital_expire_flag
  FROM cohort c
  JOIN dx d USING(hadm_id)
  WHERE (d.sepsis_flag = 1 OR d.shock_flag = 1)
),
agg AS (
  SELECT
    sepsis_group,
    los_cat,
    charlson_cat,
    COUNT(*) AS n,
    SUM(hospital_expire_flag) AS deaths,
    100.0 * SUM(hospital_expire_flag) / COUNT(*) AS mortality_pct
  FROM cohort_labeled
  GROUP BY sepsis_group, los_cat, charlson_cat
),
diffs AS (
  SELECT
    a.los_cat,
    a.charlson_cat,
    a.mortality_pct AS sepsis_mortality_pct,
    b.mortality_pct AS shock_mortality_pct,
    (b.mortality_pct - a.mortality_pct) AS abs_diff_pct,
    SAFE_DIVIDE(b.mortality_pct, a.mortality_pct) AS rel_ratio
  FROM agg a
  JOIN agg b
    ON a.los_cat = b.los_cat
   AND a.charlson_cat = b.charlson_cat
   AND a.sepsis_group = 'Sepsis without shock'
   AND b.sepsis_group = 'Septic shock'
)
SELECT *
FROM diffs
ORDER BY los_cat, charlson_cat;