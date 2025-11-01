WITH
-- 1. Female patients aged 48-58
female_48_58 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 48 AND 58
),

-- 2. Stroke ICD codes (ICD-9: 433.x1, 434.x1; ICD-10: I63.x)
stroke_admissions AS (
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN female_48_58 f ON d.subject_id = f.subject_id
  WHERE
    (
      (d.icd_version = 9 AND (
        REGEXP_CONTAINS(d.icd_code, r'^433[0-9]1$') OR
        REGEXP_CONTAINS(d.icd_code, r'^434[0-9]1$')
      ))
      OR
      (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^I63'))
    )
),

-- 3. NTI drugs list (expand as needed)
nti_drugs AS (
  SELECT 'warfarin' AS drug UNION ALL
  SELECT 'digoxin' UNION ALL
  SELECT 'phenytoin' UNION ALL
  SELECT 'carbamazepine' UNION ALL
  SELECT 'theophylline' UNION ALL
  SELECT 'tacrolimus' UNION ALL
  SELECT 'cyclosporine'
),

-- 4. CYP3A4 interacting drugs list (expand as needed)
cyp3a4_drugs AS (
  SELECT 'ketoconazole' AS drug UNION ALL
  SELECT 'clarithromycin' UNION ALL
  SELECT 'itraconazole' UNION ALL
  SELECT 'ritonavir' UNION ALL
  SELECT 'rifampin' UNION ALL
  SELECT 'voriconazole' UNION ALL
  SELECT 'diltiazem' UNION ALL
  SELECT 'verapamil'
),

-- 5. Admissions with NTI drug prescribed
nti_presc AS (
  SELECT DISTINCT p.subject_id, p.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN nti_drugs n ON LOWER(p.drug) LIKE CONCAT('%', n.drug, '%')
),

-- 6. Admissions with CYP3A4 drug prescribed
cyp3a4_presc AS (
  SELECT DISTINCT p.subject_id, p.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN cyp3a4_drugs c ON LOWER(p.drug) LIKE CONCAT('%', c.drug, '%')
),

-- 7. Admissions with both NTI and CYP3A4 drugs (potential interaction)
nti_cyp3a4_interaction AS (
  SELECT s.subject_id, s.hadm_id
  FROM stroke_admissions s
  JOIN nti_presc n ON s.subject_id = n.subject_id AND s.hadm_id = n.hadm_id
  JOIN cyp3a4_presc c ON s.subject_id = c.subject_id AND s.hadm_id = c.hadm_id
),

-- 8. Complexity score: count of unique diagnoses per admission
complexity_scores AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    COUNT(DISTINCT d.icd_code) AS complexity_score
  FROM stroke_admissions s
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON s.subject_id = d.subject_id AND s.hadm_id = d.hadm_id
  GROUP BY s.subject_id, s.hadm_id
),

-- 9. LOS and mortality for stroke admissions
stroke_metrics AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    cs.complexity_score,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    a.hospital_expire_flag
  FROM stroke_admissions s
  JOIN complexity_scores cs ON s.subject_id = cs.subject_id AND s.hadm_id = cs.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON s.subject_id = a.subject_id AND s.hadm_id = a.hadm_id
),

-- 10. Percentile calculation for complexity score
stroke_metrics_with_percentile AS (
  SELECT
    *,
    PERCENT_RANK() OVER (ORDER BY complexity_score) AS complexity_percentile
  FROM stroke_metrics
),

-- 11. Flag NTI+CYP3A4 interaction
final_stroke_cohort AS (
  SELECT
    smwp.*,
    CASE WHEN nci.subject_id IS NOT NULL THEN 1 ELSE 0 END AS nti_cyp3a4_interaction
  FROM stroke_metrics_with_percentile smwp
  LEFT JOIN nti_cyp3a4_interaction nci
    ON smwp.subject_id = nci.subject_id AND smwp.hadm_id = nci.hadm_id
)

-- 12. Aggregate results
SELECT
  'NTI+CYP3A4 interaction' AS cohort,
  COUNT(*) AS n_admissions,
  AVG(complexity_score) AS avg_complexity,
  AVG(complexity_percentile) AS avg_complexity_percentile,
  AVG(los_days) AS avg_los_days,
  SUM(hospital_expire_flag) AS n_deaths,
  AVG(hospital_expire_flag) AS mortality_rate
FROM final_stroke_cohort
WHERE nti_cyp3a4_interaction = 1

UNION ALL

SELECT
  'All stroke admissions (age-matched)' AS cohort,
  COUNT(*) AS n_admissions,
  AVG(complexity_score) AS avg_complexity,
  AVG(complexity_percentile) AS avg_complexity_percentile,
  AVG(los_days) AS avg_los_days,
  SUM(hospital_expire_flag) AS n_deaths,
  AVG(hospital_expire_flag) AS mortality_rate
FROM final_stroke_cohort

UNION ALL

SELECT
  'Top quartile complexity (stroke)' AS cohort,
  COUNT(*) AS n_admissions,
  AVG(complexity_score) AS avg_complexity,
  AVG(complexity_percentile) AS avg_complexity_percentile,
  AVG(los_days) AS avg_los_days,
  SUM(hospital_expire_flag) AS n_deaths,
  AVG(hospital_expire_flag) AS mortality_rate
FROM final_stroke_cohort
WHERE complexity_percentile >= 0.75;