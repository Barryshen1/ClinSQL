WITH stroke_admissions AS (
  -- 1. Select acute ischemic stroke admissions for females aged 48-58
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    dc.long_title AS diagnosis_desc
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dc
      ON di.icd_code = dc.icd_code
      AND di.icd_version = dc.icd_version
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON di.subject_id = a.subject_id
      AND di.hadm_id = a.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    dc.icd_code LIKE 'I63%'      -- acute cerebral infarction
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 48 AND 58
),
stroke_with_drugs AS (
  -- 2. Mark admissions with at least one CYP3A4-interacting NTI drug prescription
  SELECT
    sa.*,
    CASE
      WHEN COUNT(*) > 0 THEN 1
      ELSE 0
    END AS has_cyp3a4_nti
  FROM
    stroke_admissions sa
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
      ON sa.subject_id = pr.subject_id
      AND sa.hadm_id = pr.hadm_id
      AND pr.starttime BETWEEN sa.admittime AND sa.dischtime
      AND pr.drug IN UNNEST([
        'Tacrolimus',
        'Cyclosporine',
        'Warfarin',
        'Theophylline',
        'Carbamazepine',
        'Phenytoin'
      ])
  GROUP BY
    sa.subject_id,
    sa.hadm_id,
    sa.admittime,
    sa.dischtime,
    sa.hospital_expire_flag,
    sa.gender,
    sa.anchor_age,
    sa.diagnosis_desc
),
stroke_cohort AS (
  -- 3. Attach DRG severity as complexity score and calculate LOS
  SELECT
    swd.*,
    dc.drg_severity AS complexity_score,
    DATE_DIFF(swd.dischtime, swd.admittime, DAY) AS los_days
  FROM
    stroke_with_drugs swd
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.drgcodes` dc
      ON swd.subject_id = dc.subject_id
      AND swd.hadm_id = dc.hadm_id
),
percentiles AS (
  -- 4. Compute percentile of complexity score within cohort
  SELECT
    sc.*,
    PERCENT_RANK() OVER (ORDER BY complexity_score) * 100.0 AS complexity_pct
  FROM
    stroke_cohort sc
),
top_quartile AS (
  -- 5. Filter top 25% by complexity percentile
  SELECT
    *,
    CASE WHEN complexity_pct > 75 THEN 'Top Quartile' ELSE 'Other' END AS quartile_group
  FROM
    percentiles
)
-- 6. Final report: Compare LOS and mortality in top quartile, by drug-interaction cohort
SELECT
  quartile_group,
  has_cyp3a4_nti,
  COUNT(*) AS n_patients,
  AVG(los_days) AS avg_los_days,
  SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*)) AS mortality_rate
FROM
  top_quartile
WHERE
  quartile_group = 'Top Quartile'
GROUP BY
  quartile_group,
  has_cyp3a4_nti
ORDER BY
  has_cyp3a4_nti;