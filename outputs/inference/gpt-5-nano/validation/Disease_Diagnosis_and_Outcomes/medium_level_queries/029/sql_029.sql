WITH eligible AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) + 1 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 57 AND 67
),

-- Part 2: identify sepsis vs septic shock per admission
sepsis_flags AS (
  SELECT i.hadm_id,
         MAX(CASE
               WHEN (d.icd_version = 10 AND (d.icd_code LIKE 'A41%' OR d.icd_code LIKE 'A40%'))
                    OR (d.icd_version = 9  AND (d.icd_code LIKE '038%' OR d.icd_code LIKE '995%' OR d.icd_code LIKE '785.52%'))
               THEN 1 ELSE 0 END) AS sepsis,
         MAX(CASE
               WHEN (d.icd_version = 10 AND d.icd_code LIKE 'R65.2%')
                    OR (d.icd_version = 9  AND (d.icd_code LIKE '785.52%'))
               THEN 1 ELSE 0 END) AS septic_shock
  FROM eligible AS i
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON i.hadm_id = d.hadm_id
  GROUP BY i.hadm_id
),

-- Part 3: define septic groups (only those with sepsis)
cohort AS (
  SELECT
    e.hadm_id,
    e.subject_id,
    e.admittime,
    e.dischtime,
    e.hospital_expire_flag,
    e.los_days,
    CASE
      WHEN s.sepsis = 1 AND s.septic_shock = 0 THEN 'Sepsis_without_shock'
      WHEN s.sepsis = 1 AND s.septic_shock = 1 THEN 'Septic_shock'
      ELSE NULL
    END AS group_label
  FROM eligible e
  JOIN sepsis_flags s
    ON e.hadm_id = s.hadm_id
  WHERE s.sepsis = 1
),

-- Part 4: Charlson components per admission (weighted, simplified)
charlson_by_hadm AS (
  SELECT
    d.hadm_id,
    MAX(CASE WHEN (d.icd_version = 10 AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%' OR d.icd_code LIKE 'I25%'))
             THEN 1 ELSE 0 END) AS mi_present,
    MAX(CASE WHEN ((d.icd_version = 10 AND (d.icd_code LIKE 'I50%')) OR (d.icd_version = 9 AND (d.icd_code LIKE '428%')))
             THEN 1 ELSE 0 END) AS chf_present,
    MAX(CASE WHEN ((d.icd_version = 10 AND (d.icd_code LIKE 'I70%' OR d.icd_code LIKE 'I73%')) OR (d.icd_version = 9 AND (d.icd_code LIKE '440%' OR d.icd_code LIKE '441%' OR d.icd_code LIKE '442%' OR d.icd_code LIKE '443%' OR d.icd_code LIKE '444%' OR d.icd_code LIKE '447%')))
             THEN 1 ELSE 0 END) AS pvd_present,
    MAX(CASE WHEN ((d.icd_version = 10 AND (d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I63%' OR d.icd_code LIKE 'I69%')) OR (d.icd_version = 9 AND (d.icd_code LIKE '430%' OR d.icd_code LIKE '431%' OR d.icd_code LIKE '432%' OR d.icd_code LIKE '434%' OR d.icd_code LIKE '435%' OR d.icd_code LIKE '436%')))
             THEN 1 ELSE 0 END) AS cerebro_present,
    MAX(CASE WHEN ((d.icd_version = 10 AND (d.icd_code LIKE 'F01%' OR d.icd_code LIKE 'F03%')) OR (d.icd_version = 9 AND (d.icd_code LIKE '290%')))
             THEN 1 ELSE 0 END) AS dementia_present,
    MAX(CASE WHEN ((d.icd_version = 10 AND (d.icd_code LIKE 'J44%' OR d.icd_code LIKE 'J40%')) OR (d.icd_version = 9 AND (d.icd_code LIKE '490%' OR d.icd_code LIKE '491%' OR d.icd_code LIKE '492%' OR d.icd_code LIKE '493%' OR d.icd_code LIKE '494%' OR d.icd_code LIKE '495%' OR d.icd_code LIKE '496%')))
             THEN 1 ELSE 0 END) AS copd_present,
    MAX(CASE WHEN ((d.icd_version = 10 AND (d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E08%' OR d.icd_code LIKE 'E09%')) OR (d.icd_version = 9 AND (d.icd_code LIKE '250.0%' OR d.icd_code LIKE '250.1%' OR d.icd_code LIKE '250.2%' OR d.icd_code LIKE '250.3%')))
             THEN 1 ELSE 0 END) AS diabetes_no_comp_present,
    MAX(CASE WHEN ((d.icd_version = 10 AND (d.icd_code LIKE 'E10.6%' OR d.icd_code LIKE 'E11.6%')) OR (d.icd_version = 9 AND (d.icd_code LIKE '250.4%' OR d.icd_code LIKE '250.5%')))
             THEN 1 ELSE 0 END) AS diabetes_with_comp_present,
    MAX(CASE WHEN ((d.icd_version = 10 AND (d.icd_code LIKE 'N18%' OR d.icd_code LIKE 'N19%')) OR (d.icd_version = 9 AND (d.icd_code LIKE '580%' OR d.icd_code LIKE '581%' OR d.icd_code LIKE '582%' OR d.icd_code LIKE '585%' OR d.icd_code LIKE '586%')))
             THEN 1 ELSE 0 END) AS renal_present,
    MAX(CASE WHEN ((d.icd_version = 10 AND (d.icd_code LIKE 'K70%' OR d.icd_code LIKE 'K71%' OR d.icd_code LIKE 'K72%' OR d.icd_code LIKE 'K73%' OR d.icd_code LIKE 'K74%' OR d.icd_code LIKE 'K76%' OR d.icd_code LIKE 'K77%')) OR (d.icd_version = 9 AND (d.icd_code LIKE '571%' OR d.icd_code LIKE '573%')))
             THEN 1 ELSE 0 END) AS liver_present,
    MAX(CASE WHEN ((d.icd_version = 10 AND (d.icd_code LIKE 'C77%' OR d.icd_code LIKE 'C78%' OR d.icd_code LIKE 'C79%')) OR (d.icd_version = 9 AND (d.icd_code LIKE '140%' OR d.icd_code LIKE '150%' OR d.icd_code LIKE '160%' OR d.icd_code LIKE '170%' OR d.icd_code LIKE '180%' OR d.icd_code LIKE '190%' OR d.icd_code LIKE '200%' OR d.icd_code LIKE '205%' OR d.icd_code LIKE '208%')))
             THEN 1 ELSE 0 END) AS solid_tumor_present,
    MAX(CASE WHEN ((d.icd_version = 10 AND (d.icd_code LIKE 'C79%' OR d.icd_code LIKE 'C77%')) OR (d.icd_version = 9 AND (d.icd_code LIKE '196%' OR d.icd_code LIKE '197%' OR d.icd_code LIKE '198%')))
             THEN 1 ELSE 0 END) AS metastasis_present,
    MAX(CASE WHEN ((d.icd_version = 10 AND (d.icd_code LIKE 'B20%' OR d.icd_code LIKE 'B24%')) OR (d.icd_version = 9 AND (d.icd_code LIKE '042%')))
             THEN 1 ELSE 0 END) AS aids_present
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  GROUP BY d.hadm_id
),

charlson_calc AS (
  SELECT
    h.hadm_id,
    (COALESCE(mi_present,0)*1
     + COALESCE(chf_present,0)*1
     + COALESCE(pvd_present,0)*1
     + COALESCE(cerebro_present,0)*1
     + COALESCE(dementia_present,0)*1
     + COALESCE(copd_present,0)*1
     + COALESCE(diabetes_no_comp_present,0)*1
     + COALESCE(diabetes_with_comp_present,0)*2
     + COALESCE(renal_present,0)*2
     + COALESCE(liver_present,0)*3
     + COALESCE(solid_tumor_present,0)*2
     + COALESCE(metastasis_present,0)*6
     + COALESCE(aids_present,0)*6
    ) AS charlson_score
  FROM charlson_by_hadm AS h
),

per_admission AS (
  SELECT
    coh.group_label,
    CASE
      WHEN e.los_days <= 7 THEN 'LOS_7_or_less'
      ELSE 'LOS_greater7'
    END AS los_bucket,
    CASE
      WHEN cc.charlson_score <= 3 THEN '0-3'
      WHEN cc.charlson_score BETWEEN 4 AND 5 THEN '4-5'
      ELSE '>5'
    END AS charlson_bucket,
    e.hadm_id,
    e.hospital_expire_flag
  FROM cohort AS coh
  JOIN eligible AS e ON coh.hadm_id = e.hadm_id
  JOIN charlson_calc AS cc ON e.hadm_id = cc.hadm_id
)

-- Part 5 (final): summarize mortality by group, LOS bucket, and Charlson bucket
SELECT
  los_bucket,
  charlson_bucket,
  SUM(CASE WHEN group_label = 'Sepsis_without_shock' THEN hospital_expire_flag ELSE 0 END)
    / NULLIF(SUM(CASE WHEN group_label = 'Sepsis_without_shock' THEN 1 ELSE 0 END), 0) * 100 AS mortality_no_shock_pct,
  SUM(CASE WHEN group_label = 'Septic_shock' THEN hospital_expire_flag ELSE 0 END)
    / NULLIF(SUM(CASE WHEN group_label = 'Septic_shock' THEN 1 ELSE 0 END), 0) * 100 AS mortality_shock_pct,
  ABS(
    (SUM(CASE WHEN group_label = 'Septic_shock' THEN hospital_expire_flag ELSE 0 END)
     / NULLIF(SUM(CASE WHEN group_label = 'Septic_shock' THEN 1 ELSE 0 END), 0) * 100)
    -
    (SUM(CASE WHEN group_label = 'Sepsis_without_shock' THEN hospital_expire_flag ELSE 0 END)
     / NULLIF(SUM(CASE WHEN group_label = 'Sepsis_without_shock' THEN 1 ELSE 0 END), 0) * 100)
  ) AS abs_diff_pct,
  SAFE_DIVIDE(
     ABS(
       (SUM(CASE WHEN group_label = 'Septic_shock' THEN hospital_expire_flag ELSE 0 END)
        / NULLIF(SUM(CASE WHEN group_label = 'Septic_shock' THEN 1 ELSE 0 END), 0) * 100)
       -
       (SUM(CASE WHEN group_label = 'Sepsis_without_shock' THEN hospital_expire_flag ELSE 0 END)
        / NULLIF(SUM(CASE WHEN group_label = 'Sepsis_without_shock' THEN 1 ELSE 0 END), 0) * 100)
     ),
     NULLIF(
       (SUM(CASE WHEN group_label = 'Sepsis_without_shock' THEN hospital_expire_flag ELSE 0 END)
        / NULLIF(SUM(CASE WHEN group_label = 'Sepsis_without_shock' THEN 1 ELSE 0 END), 0) * 100),
       0
     )
  ) AS relative_diff
FROM per_admission
GROUP BY los_bucket, charlson_bucket
ORDER BY los_bucket, charlson_bucket;