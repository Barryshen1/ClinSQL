WITH stroke_cohort AS (
  -- Base cohort: females 48-58 with principal acute ischemic stroke (ICD-10 I63*)
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(COALESCE(a.dischtime, a.admittime + INTERVAL 1 DAY), a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 48 AND 58
    AND d.icd_version = '10'
    AND d.icd_code LIKE 'I63%'  -- Acute ischemic stroke
    AND d.seq_num = 1  -- Principal diagnosis
    AND a.admission_type != 'OBSERVATION'  -- Inpatient only
),

interaction_flag AS (
  -- Flag CYP3A4 interaction: any NTI drug overlaps any inhibitor during admission
  SELECT 
    sc.*,
    CASE 
      WHEN EXISTS (
        SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` nti
        WHERE nti.hadm_id = sc.hadm_id
          AND (nti.drug LIKE '%simvastatin%' OR nti.drug LIKE '%warfarin%' 
               OR nti.formulary_drug_cd IN ('SIMVASTATIN', 'WARFARIN'))
          AND nti.starttime <= sc.dischtime
          AND COALESCE(nti.stoptime, nti.starttime + INTERVAL 7 DAY) >= sc.admittime
      ) AND EXISTS (
        SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` inhib
        WHERE inhib.hadm_id = sc.hadm_id
          AND (inhib.drug LIKE '%clarithromycin%' OR inhib.drug LIKE '%ketoconazole%' OR inhib.drug LIKE '%erythromycin%')
          AND inhib.starttime <= sc.dischtime
          AND COALESCE(inhib.stoptime, inhib.starttime + INTERVAL 7 DAY) >= sc.admittime
      ) THEN 1 ELSE 0 
    END AS has_cyp3a4_interaction
  FROM stroke_cohort sc
),

complexity_base AS (
  -- Compute complexity score (num distinct diagnoses) per admission
  SELECT 
    iflag.*,
    COUNT(DISTINCT diag.icd_code) AS complexity_score
  FROM interaction_flag iflag
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON iflag.subject_id = diag.subject_id 
    AND iflag.hadm_id = diag.hadm_id
    AND diag.icd_version = '10'  -- All diagnoses for complexity
  GROUP BY 
    iflag.subject_id, iflag.hadm_id, iflag.anchor_age, iflag.admittime, iflag.dischtime,
    iflag.hospital_expire_flag, iflag.los_days, iflag.has_cyp3a4_interaction
),

complexity_metrics AS (
  -- Add percentile ranking within cohort
  SELECT 
    *,
    PERCENT_RANK() OVER (ORDER BY complexity_score DESC) AS complexity_percentile
  FROM complexity_base
)

-- Part 1 & 2: Comparison for age-matched cohort (48-58F stroke)
SELECT 
  'Complexity Score (Avg)' AS metric,
  ROUND(AVG(CASE WHEN has_cyp3a4_interaction = 0 THEN complexity_score END), 2) AS no_interaction,
  ROUND(AVG(CASE WHEN has_cyp3a4_interaction = 1 THEN complexity_score END), 2) AS with_interaction
FROM complexity_metrics
UNION ALL
SELECT 
  'Complexity Percentile (Avg)',
  ROUND(AVG(CASE WHEN has_cyp3a4_interaction = 0 THEN complexity_percentile END), 3),
  ROUND(AVG(CASE WHEN has_cyp3a4_interaction = 1 THEN complexity_percentile END), 3)
FROM complexity_metrics
UNION ALL
SELECT 
  'LOS (Avg Days)',
  ROUND(AVG(CASE WHEN has_cyp3a4_interaction = 0 THEN los_days END), 2),
  ROUND(AVG(CASE WHEN has_cyp3a4_interaction = 1 THEN los_days END), 2)
FROM complexity_metrics
UNION ALL
SELECT 
  'Mortality Rate (%)',
  ROUND(100.0 * AVG(CASE WHEN has_cyp3a4_interaction = 0 THEN hospital_expire_flag END), 2),
  ROUND(100.0 * AVG(CASE WHEN has_cyp3a4_interaction = 1 THEN hospital_expire_flag END), 2)
FROM complexity_metrics

-- Part 3: LOS and mortality for stroke patients in top quartile of complexity (all stroke patients, no age/gender limit)
UNION ALL
SELECT 
  'Top Quartile Stroke - LOS (Avg Days)' AS metric,
  ROUND(AVG(los_days), 2) AS no_interaction,
  NULL AS with_interaction
FROM (
  WITH all_stroke AS (
    SELECT 
      a.hadm_id,
      DATE_DIFF(COALESCE(a.dischtime, a.admittime + INTERVAL 1 DAY), a.admittime, DAY) AS los_days,
      a.hospital_expire_flag,
      COUNT(DISTINCT d.icd_code) AS complexity_score
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
    WHERE d.icd_version = '10'
      AND d.icd_code LIKE 'I63%'
      AND d.seq_num = 1
      AND a.admission_type != 'OBSERVATION'
    GROUP BY a.hadm_id, a.dischtime, a.hospital_expire_flag, a.admittime
  ),
  top_quartile AS (
    SELECT *
    FROM (
      SELECT *, NTILE(4) OVER (ORDER BY complexity_score DESC) AS quartile
      FROM all_stroke
    )
    WHERE quartile = 1
  )
  SELECT los_days, hospital_expire_flag
  FROM top_quartile
)
UNION ALL
SELECT 
  'Top Quartile Stroke - Mortality Rate (%)' AS metric,
  ROUND(100.0 * AVG(hospital_expire_flag), 2),
  NULL
FROM (
  WITH all_stroke AS (
    SELECT 
      a.hadm_id,
      DATE_DIFF(COALESCE(a.dischtime, a.admittime + INTERVAL 1 DAY), a.admittime, DAY) AS los_days,
      a.hospital_expire_flag,
      COUNT(DISTINCT d.icd_code) AS complexity_score
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
    WHERE d.icd_version = '10'
      AND d.icd_code LIKE 'I63%'
      AND d.seq_num = 1
      AND a.admission_type != 'OBSERVATION'
    GROUP BY a.hadm_id, a.dischtime, a.hospital_expire_flag, a.admittime
  ),
  top_quartile AS (
    SELECT *
    FROM (
      SELECT *, NTILE(4) OVER (ORDER BY complexity_score DESC) AS quartile
      FROM all_stroke
    )
    WHERE quartile = 1
  )
  SELECT hospital_expire_flag
  FROM top_quartile
);