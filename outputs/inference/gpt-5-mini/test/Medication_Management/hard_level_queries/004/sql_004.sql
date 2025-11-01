WITH stroke_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- LOS in fractional days
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    USING(subject_id)
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 48 AND 58
    -- admission has at least one diagnosis indicating acute ischemic stroke
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND (
          -- ICD-10 I63.* acute ischemic stroke family
          (d.icd_version = 10 AND d.icd_code LIKE 'I63%')
          -- common ICD-9 ischemic stroke codes (433,434 family)
          OR (d.icd_version = 9 AND (d.icd_code LIKE '433%' OR d.icd_code LIKE '434%'))
          -- fallback by diagnosis title text
          OR LOWER(COALESCE(dd.long_title, '')) LIKE '%ischemic stroke%'
        )
    )
),

complexity_and_interaction AS (
  SELECT
    sa.*,
    -- complexity score proxy: number of distinct diagnosis codes for the admission
    (
      SELECT COUNT(DISTINCT d.icd_code)
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = sa.hadm_id
    ) AS complexity_score,
    -- flag potential CYP3A4 x NTI co-prescription (overlapping prescription windows)
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p_nti
        JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p_mod
          ON p_nti.hadm_id = p_mod.hadm_id
        WHERE p_nti.hadm_id = sa.hadm_id
          -- NTI drugs that are commonly CYP3A4 substrates (example list)
          AND (
            LOWER(COALESCE(p_nti.drug, '')) LIKE '%tacrolimus%'
            OR LOWER(COALESCE(p_nti.drug, '')) LIKE '%cyclosporine%'
            OR LOWER(COALESCE(p_nti.drug, '')) LIKE '%sirolimus%'
          )
          -- CYP3A4 inhibitors/inducers (example list)
          AND (
            LOWER(COALESCE(p_mod.drug, '')) LIKE '%ketoconazole%'
            OR LOWER(COALESCE(p_mod.drug, '')) LIKE '%itraconazole%'
            OR LOWER(COALESCE(p_mod.drug, '')) LIKE '%fluconazole%'
            OR LOWER(COALESCE(p_mod.drug, '')) LIKE '%clarithromycin%'
            OR LOWER(COALESCE(p_mod.drug, '')) LIKE '%erythromycin%'
            OR LOWER(COALESCE(p_mod.drug, '')) LIKE '%ritonavir%'
            OR LOWER(COALESCE(p_mod.drug, '')) LIKE '%rifampin%'
            OR LOWER(COALESCE(p_mod.drug, '')) LIKE '%carbamazepine%'
            OR LOWER(COALESCE(p_mod.drug, '')) LIKE '%phenytoin%'
            OR LOWER(COALESCE(p_mod.drug, '')) LIKE '%phenobarb%'
          )
          -- overlapping time windows within the admission (use admission bounds when times missing)
          AND COALESCE(p_nti.stoptime, sa.dischtime) > COALESCE(p_mod.starttime, sa.admittime)
          AND COALESCE(p_mod.stoptime, sa.dischtime) > COALESCE(p_nti.starttime, sa.admittime)
      ) THEN 1 ELSE 0
    END AS cyp3a4_interaction
  FROM stroke_admissions sa
),

with_percentile AS (
  SELECT
    *,
    PERCENT_RANK() OVER (ORDER BY complexity_score) AS complexity_percentile
  FROM complexity_and_interaction
)

-- Combine both outputs into a single statement so the CTEs are in scope for both parts.
SELECT
  'interaction_group_comparison' AS analysis,
  CAST(cyp3a4_interaction AS STRING) AS interaction_flag,
  COUNT(*) AS n_admissions,
  ROUND(AVG(complexity_score), 2) AS avg_complexity_score,
  -- approximate median complexity score
  APPROX_QUANTILES(complexity_score, 100)[OFFSET(50)] AS median_complexity_score_approx,
  ROUND(AVG(complexity_percentile), 4) AS avg_complexity_percentile,
  ROUND(AVG(los_days), 2) AS avg_los_days,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_days_approx,
  ROUND(SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*)), 4) AS in_hospital_mortality_rate
FROM with_percentile
GROUP BY cyp3a4_interaction

UNION ALL

SELECT
  'top_quartile_summary' AS analysis,
  'top_quartile' AS interaction_flag,
  COUNT(*) AS n_admissions,
  ROUND(AVG(complexity_score), 2) AS avg_complexity_score,
  APPROX_QUANTILES(complexity_score, 100)[OFFSET(50)] AS median_complexity_score_approx,
  ROUND(AVG(complexity_percentile), 4) AS avg_complexity_percentile,
  ROUND(AVG(los_days), 2) AS avg_los_days,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_days_approx,
  ROUND(SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*)), 4) AS in_hospital_mortality_rate
FROM with_percentile
WHERE complexity_percentile >= 0.75

ORDER BY analysis DESC, interaction_flag DESC;