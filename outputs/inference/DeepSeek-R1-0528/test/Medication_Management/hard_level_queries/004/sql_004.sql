WITH
  nti_drugs AS (
    SELECT * FROM UNNEST([
      'warfarin', 'digoxin', 'phenytoin', 'carbamazepine', 'lithium', 'theophylline',
      'valproic acid', 'levothyroxine', 'cyclosporine', 'tacrolimus'
    ]) AS drug_name
  ),
  cyp3a4_modulators AS (
    SELECT * FROM UNNEST([
      'ketoconazole', 'itraconazole', 'voriconazole', 'clarithromycin', 'erythromycin',
      'diltiazem', 'verapamil', 'grapefruit', 'fluconazole', 'nefazodone', 'ritonavir',
      'indinavir', 'saquinavir', 'nelfinavir', 'atazanavir', 'telithromycin', 'conivaptan',
      'imatinib', 'cimetidine', 'cobicistat', 'rifampin', 'rifampicin', 'carbamazepine',
      'phenytoin', 'phenobarbital', 'primidone', 'rifabutin', 'dexamethasone', 'prednisone',
      'St. John\'s wort'
    ]) AS drug_name
  ),
  base_cohort AS (
    SELECT
      p.subject_id,
      p.gender,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.hospital_expire_flag,
      p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
    WHERE
      p.gender = 'F'
      AND EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        WHERE
          di.subject_id = a.subject_id
          AND di.hadm_id = a.hadm_id
          AND (
            (di.icd_version = 9 AND REGEXP_CONTAINS(di.icd_code, r'^(433.[01]1|434.[01]1|434.91|436)'))
            OR (di.icd_version = 10 AND REGEXP_CONTAINS(di.icd_code, r'^(I63|I64)'))
          )
      )
  ),
  filtered_cohort AS (
    SELECT *
    FROM base_cohort
    WHERE age_at_admission BETWEEN 48 AND 58
  ),
  prescriptions_nti AS (
    SELECT
      pr.hadm_id,
      MAX(CASE WHEN LOWER(pr.drug) IN (SELECT LOWER(drug_name) FROM nti_drugs) THEN 1 ELSE 0 END) AS has_nti
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    WHERE pr.hadm_id IN (SELECT hadm_id FROM filtered_cohort)
    GROUP BY pr.hadm_id
  ),
  prescriptions_cyp AS (
    SELECT
      pr.hadm_id,
      MAX(CASE WHEN LOWER(pr.drug) IN (SELECT LOWER(drug_name) FROM cyp3a4_modulators) THEN 1 ELSE 0 END) AS has_cyp
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    WHERE pr.hadm_id IN (SELECT hadm_id FROM filtered_cohort)
    GROUP BY pr.hadm_id
  ),
  complexity AS (
    SELECT
      hadm_id,
      MAX(SAFE_CAST(drg_severity AS INT)) AS complexity_score
    FROM `physionet-data.mimiciv_3_1_hosp.drgcodes`
    GROUP BY hadm_id
  ),
  cohort_with_flags AS (
    SELECT
      fc.*,
      DATETIME_DIFF(fc.dischtime, fc.admittime, DAY) AS los_days,
      COALESCE(pn.has_nti, 0) AS has_nti,
      COALESCE(pc.has_cyp, 0) AS has_cyp,
      c.complexity_score,
      CASE
        WHEN COALESCE(pn.has_nti, 0) = 1 AND COALESCE(pc.has_cyp, 0) = 1 THEN 'with_interaction'
        ELSE 'without_interaction'
      END AS interaction_group
    FROM filtered_cohort fc
    LEFT JOIN prescriptions_nti pn ON fc.hadm_id = pn.hadm_id
    LEFT JOIN prescriptions_cyp pc ON fc.hadm_id = pc.hadm_id
    LEFT JOIN complexity c ON fc.hadm_id = c.hadm_id
    WHERE c.complexity_score IS NOT NULL
  ),
  pct_75 AS (
    SELECT
      APPROX_QUANTILES(complexity_score, 100)[OFFSET(75)] AS pct_75_value
    FROM cohort_with_flags
  )
-- Entire cohort comparison
SELECT
  'entire_cohort' AS cohort_type,
  interaction_group,
  COUNT(*) AS n_patients,
  APPROX_QUANTILES(complexity_score, 4)[OFFSET(2)] AS median_complexity,
  APPROX_QUANTILES(complexity_score, 4)[OFFSET(1)] AS q1_complexity,
  APPROX_QUANTILES(complexity_score, 4)[OFFSET(3)] AS q3_complexity,
  APPROX_QUANTILES(los_days, 4)[OFFSET(2)] AS median_los,
  APPROX_QUANTILES(los_days, 4)[OFFSET(1)] AS q1_los,
  APPROX_QUANTILES(los_days, 4)[OFFSET(3)] AS q3_los,
  SUM(hospital_expire_flag) AS deaths,
  AVG(hospital_expire_flag) AS mortality_rate
FROM cohort_with_flags
GROUP BY interaction_group

UNION ALL

-- Top quartile analysis (LOS and mortality only)
SELECT
  'top_quartile' AS cohort_type,
  interaction_group,
  COUNT(*) AS n_patients,
  NULL AS median_complexity,
  NULL AS q1_complexity,
  NULL AS q3_complexity,
  APPROX_QUANTILES(los_days, 4)[OFFSET(2)] AS median_los,
  APPROX_QUANTILES(los_days, 4)[OFFSET(1)] AS q1_los,
  APPROX_QUANTILES(los_days, 4)[OFFSET(3)] AS q3_los,
  SUM(hospital_expire_flag) AS deaths,
  AVG(hospital_expire_flag) AS mortality_rate
FROM cohort_with_flags
CROSS JOIN pct_75
WHERE complexity_score >= pct_75_value
GROUP BY interaction_group;