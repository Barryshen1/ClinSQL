WITH ami_codes AS (
  -- ICD codes for AMI (primary diagnosis)
  SELECT icd_code FROM UNNEST(['41000', '41001', '41002', '41010', '41011', '41012', '41020', '41021', '41022', '41030', '41031', '41032', '41040', '41041', '41042', '41050', '41051', '41052', '41060', '41061', '41062', '41070', '41071', '41072', '41080', '41081', '41082', '41090', '41091', '41092', 'I210', 'I211', 'I212', 'I213', 'I214', 'I219']) AS icd_code
),
target_cohort AS (
  -- Females 68-78 with primary AMI and ICU stay
  SELECT DISTINCT p.subject_id, p.anchor_age, a.hadm_id, a.admittime, a.dischtime, a.deathtime, c.stay_id, c.intime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` c ON a.subject_id = c.subject_id AND a.hadm_id = c.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  INNER JOIN ami_codes ac ON d.icd_code = ac.icd_code
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
    AND d.seq_num = 1
),
general_cohort AS (
  -- Age-matched general females with ICU (exclude primary AMI)
  SELECT DISTINCT p.subject_id, p.anchor_age, a.hadm_id, a.admittime, a.dischtime, a.deathtime, c.stay_id, c.intime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` c ON a.subject_id = c.subject_id AND a.hadm_id = c.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
    AND NOT EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      INNER JOIN ami_codes ac ON d.icd_code = ac.icd_code
      WHERE d.subject_id = a.subject_id AND d.hadm_id = a.hadm_id AND d.seq_num = 1
    )
),
vitals_agg AS (
  -- Aggregate first 24h vitals per stay for risk score
  SELECT 
    subject_id, hadm_id, stay_id,
    AVG(CASE WHEN itemid = 220045 THEN valuenum END) AS avg_hr,  -- Heart rate
    AVG(CASE WHEN itemid = 220179 THEN valuenum END) AS avg_sbp,  -- Systolic BP
    AVG(CASE WHEN itemid = 618 THEN valuenum END) AS avg_rr,      -- Respiratory rate
    AVG(CASE WHEN itemid = 676 THEN valuenum END) AS avg_temp,    -- Temperature
    AVG(CASE WHEN itemid = 228139 THEN valuenum END) AS avg_gcs,  -- GCS total
    AVG(CASE WHEN itemid = 50912 THEN valuenum END) AS avg_creat, -- Creatinine
    AVG(CASE WHEN itemid = 51301 THEN valuenum END) AS avg_wbc,   -- WBC
    AVG(CASE WHEN itemid = 50809 THEN valuenum END) AS avg_na,    -- Sodium
    AVG(CASE WHEN itemid = 51221 THEN valuenum END) AS avg_hct    -- Hematocrit
  FROM `physionet-data.mimiciv_3_1_icu.chartevents`
  WHERE itemid IN (220045, 220179, 618, 676, 228139, 50912, 51301, 50809, 51221)
    AND valuenum IS NOT NULL
  GROUP BY subject_id, hadm_id, stay_id
),
risk_scores AS (
  -- Simplified risk score from first 24h ICU vitals (APACHE proxy: age + 9 vitals binned)
  SELECT 
    tc.subject_id, tc.hadm_id, tc.stay_id, tc.anchor_age,
    tc.anchor_age + 
    COALESCE(
      (CASE WHEN va.avg_hr > 100 THEN 2 ELSE 0 END) +
      (CASE WHEN va.avg_sbp < 70 THEN 2 ELSE 0 END) +
      (CASE WHEN va.avg_rr > 20 THEN 2 ELSE 0 END) +
      (CASE WHEN va.avg_temp < 96 THEN 2 ELSE 0 END) +
      (CASE WHEN ABS(COALESCE(va.avg_gcs, 15) - 15) > 3 THEN 5 ELSE 0 END) +
      (CASE WHEN va.avg_creat > 1.5 THEN 3 ELSE 0 END) +
      (CASE WHEN va.avg_wbc > 20 THEN 2 ELSE 0 END) +
      (CASE WHEN va.avg_na < 130 THEN 2 ELSE 0 END) +
      (CASE WHEN va.avg_hct < 30 THEN 3 ELSE 0 END),
      0
    ) AS risk_score
  FROM target_cohort tc
  LEFT JOIN vitals_agg va ON tc.subject_id = va.subject_id AND tc.hadm_id = va.hadm_id AND tc.stay_id = va.stay_id
),
mace_complications AS (
  -- Major complications (MACE proxy: CABG, IABP, or high troponin)
  SELECT 
    tc.subject_id, tc.hadm_id,
    MAX(CASE 
      WHEN EXISTS (
        SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr 
        WHERE pr.subject_id = tc.subject_id AND pr.hadm_id = tc.hadm_id 
          AND (pr.icd_code LIKE '36.0%' OR pr.icd_code LIKE '37.2%' OR pr.icd_code LIKE '02C%' OR pr.icd_code LIKE '5A1%')
      ) 
      OR EXISTS (
        SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.labevents` l 
        INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li ON l.itemid = li.itemid
        WHERE l.subject_id = tc.subject_id AND l.hadm_id = tc.hadm_id 
          AND li.label LIKE '%troponin%' AND l.valuenum > 0.4
        GROUP BY l.subject_id, l.hadm_id
        HAVING MAX(l.valuenum) > 0.4
      ) THEN 1 ELSE 0 
    END) AS has_mace
  FROM target_cohort tc
  GROUP BY tc.subject_id, tc.hadm_id
),
mortality_90d AS (
  -- 90-day mortality
  SELECT 
    tc.subject_id, tc.hadm_id,
    CASE 
      WHEN tc.deathtime IS NOT NULL AND TIMESTAMP_DIFF(TIMESTAMP(tc.deathtime), TIMESTAMP(tc.admittime), DAY) <= 90 THEN 1
      WHEN p.dod IS NOT NULL AND DATE(p.dod) <= DATE_ADD(DATE(tc.admittime), INTERVAL 90 DAY) THEN 1
      ELSE 0 
    END AS died_90d
  FROM target_cohort tc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON tc.subject_id = p.subject_id
),
target_metrics AS (
  SELECT 
    'Target (AMI Females 68-78)' AS cohort,
    PERCENTILE_CONT(risk_score, 0.5) AS median_risk,
    PERCENTILE_CONT(risk_score, 0.25) AS iqr_risk_lower,
    PERCENTILE_CONT(risk_score, 0.75) AS iqr_risk_upper,
    AVG(m.died_90d) * 100 AS mortality_90d_pct,
    AVG(mc.has_mace) * 100 AS mace_rate_pct,
    PERCENTILE_CONT(c.los, 0.5) FILTER (WHERE m.died_90d = 0) AS median_los_days
  FROM risk_scores rs
  INNER JOIN mortality_90d m ON rs.subject_id = m.subject_id AND rs.hadm_id = m.hadm_id
  INNER JOIN mace_complications mc ON rs.subject_id = mc.subject_id AND rs.hadm_id = mc.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` c ON rs.subject_id = c.subject_id AND rs.hadm_id = c.hadm_id AND rs.stay_id = c.stay_id
),
general_mace AS (
  -- MACE for general cohort (aggregated)
  SELECT 
    gc.subject_id, gc.hadm_id,
    MAX(CASE 
      WHEN EXISTS (
        SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr 
        WHERE pr.subject_id = gc.subject_id AND pr.hadm_id = gc.hadm_id 
          AND (pr.icd_code LIKE '36.0%' OR pr.icd_code LIKE '37.2%' OR pr.icd_code LIKE '02C%' OR pr.icd_code LIKE '5A1%')
      ) 
      OR EXISTS (
        SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.labevents` l 
        INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li ON l.itemid = li.itemid
        WHERE l.subject_id = gc.subject_id AND l.hadm_id = gc.hadm_id 
          AND li.label LIKE '%troponin%' AND l.valuenum > 0.4
        GROUP BY l.subject_id, l.hadm_id
        HAVING MAX(l.valuenum) > 0.4
      ) THEN 1 ELSE 0 
    END) AS has_mace
  FROM general_cohort gc
  GROUP BY gc.subject_id, gc.hadm_id
),
general_mortality AS (
  -- Mortality for general cohort
  SELECT 
    gc.subject_id, gc.hadm_id,
    CASE 
      WHEN gc.deathtime IS NOT NULL AND TIMESTAMP_DIFF(TIMESTAMP(gc.deathtime), TIMESTAMP(gc.admittime), DAY) <= 90 THEN 1
      WHEN p.dod IS NOT NULL AND DATE(p.dod) <= DATE_ADD(DATE(gc.admittime), INTERVAL 90 DAY) THEN 1
      ELSE 0 
    END AS died_90d
  FROM general_cohort gc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON gc.subject_id = p.subject_id
),
general_metrics AS (
  SELECT 
    'General (Non-AMI Females 68-78)' AS cohort,
    AVG(gm.died_90d) * 100 AS mortality_90d_pct,
    AVG(gmace.has_mace) * 100 AS mace_rate_pct,
    PERCENTILE_CONT(c.los, 0.5) FILTER (WHERE gm.died_90d = 0) AS median_los_days
  FROM general_cohort gc
  INNER JOIN general_mortality gm ON gc.subject_id = gm.subject_id AND gc.hadm_id = gm.hadm_id
  LEFT JOIN general_mace gmace ON gc.subject_id = gmace.subject_id AND gc.hadm_id = gmace.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` c ON gc.subject_id = c.subject_id AND gc.hadm_id = c.hadm_id
),
index_percentile AS (
  -- Risk percentile for index patient (73yo female, assume risk_score=12)
  SELECT PERCENTILE_CONT(12, 0.5) WITHIN GROUP (ORDER BY risk_score) AS median_risk,
         PERCENT_RANK() OVER (ORDER BY risk_score) * 100 AS risk_percentile_for_12
  FROM risk_scores
)
SELECT 
  tm.cohort,
  tm.median_risk,
  CONCAT('(', CAST(tm.iqr_risk_lower AS STRING), ' - ', CAST(tm.iqr_risk_upper AS STRING), ')') AS risk_iqr,
  tm.mortality_90d_pct,
  tm.mace_rate_pct AS target_mace_rate,
  gm.mace_rate_pct AS general_mace_rate,
  tm.median_los_days AS target_los,
  gm.median_los_days AS general_los,
  ip.risk_percentile_for_12 AS risk_percentile
FROM target_metrics tm
CROSS JOIN index_percentile ip
LEFT JOIN general_metrics gm ON tm.cohort != gm.cohort;