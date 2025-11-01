WITH qt_drugs AS (
  SELECT * FROM UNNEST(['amiodarone','azithromycin','ciprofloxacin','clarithromycin','clozapine','disopyramide','dofetilide','domperidone','droperidol','erythromycin','flecainide','halofantrine','haloperidol','ibutilide','levomethadyl','mesoridazine','methadone','moxifloxacin','ondansetron','paliperidone','pentamidine','pimozide','procainamide','quinidine','sotalol','sparfloxacin','terfenadine','thioridazine']) AS drug_name
),
bleeding_drugs AS (
  SELECT * FROM UNNEST(['warfarin','heparin','enoxaparin','dalteparin','tinzaparin','fondaparinux','argatroban','bivalirudin','dabigatran','rivaroxaban','apixaban','edoxaban','aspirin','clopidogrel','prasugrel','ticagrelor','dipyridamole','abciximab','eptifibatide','tirofiban','ibuprofen','naproxen','diclofenac','celecoxib','meloxicam','indomethacin','ketorolac']) AS drug_name
),

-- Sepsis cohort (male, 80-90yo)
cohort AS (
  SELECT 
    p.subject_id, 
    p.gender, 
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 80 AND 90
    AND a.hadm_id IN (
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE 
        (icd_version = 9 AND icd_code IN ('99591','99592','78552'))
        OR 
        (icd_version = 10 AND icd_code IN ('A419','R6520','R6521'))
    )
),

-- Medications in first 24h with category flags
emar_meds AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    em.medication,
    MAX(CASE WHEN qt.drug_name IS NOT NULL THEN 1 ELSE 0 END) AS is_qt,
    MAX(CASE WHEN bd.drug_name IS NOT NULL THEN 1 ELSE 0 END) AS is_bleeding
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.emar` em
    ON c.hadm_id = em.hadm_id 
    AND em.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
  LEFT JOIN qt_drugs qt 
    ON LOWER(em.medication) LIKE CONCAT('%', LOWER(qt.drug_name), '%')
  LEFT JOIN bleeding_drugs bd 
    ON LOWER(em.medication) LIKE CONCAT('%', LOWER(bd.drug_name), '%')
  GROUP BY c.subject_id, c.hadm_id, em.medication
),

-- Patient-level aggregates (score and flags)
patient_meds AS (
  SELECT 
    subject_id,
    hadm_id,
    COUNT(DISTINCT medication) AS med_score,
    MAX(is_qt) AS qt_flag,
    MAX(is_bleeding) AS bleeding_flag
  FROM emar_meds
  GROUP BY subject_id, hadm_id
),

-- Combine with cohort (include patients with no meds)
cohort_meds AS (
  SELECT 
    c.*,
    COALESCE(pm.med_score, 0) AS med_score,
    COALESCE(pm.qt_flag, 0) AS qt_flag,
    COALESCE(pm.bleeding_flag, 0) AS bleeding_flag
  FROM cohort c
  LEFT JOIN patient_meds pm
    ON c.subject_id = pm.subject_id AND c.hadm_id = pm.hadm_id
),

-- Add group flag (1 = on both QT & bleeding drugs)
cohort_groups AS (
  SELECT *,
    CASE WHEN qt_flag = 1 AND bleeding_flag = 1 THEN 1 ELSE 0 END AS group_flag
  FROM cohort_meds
),

-- Part A: Score distribution by group
part_a AS (
  SELECT 
    group_flag,
    COUNT(*) AS n_patients,
    MIN(med_score) AS min_score,
    MAX(med_score) AS max_score,
    AVG(med_score) AS avg_score,
    APPROX_QUANTILES(med_score, 4) AS quartiles  -- [min, Q1, median, Q3, max]
  FROM cohort_groups
  GROUP BY group_flag
),

-- Part B: Top quartile outcomes (entire cohort)
top_quartile_threshold AS (
  SELECT 
    APPROX_QUANTILES(med_score, 4)[OFFSET(3)] AS q3_value
  FROM cohort_groups
),
top_quartile_patients AS (
  SELECT 
    cg.*,
    DATE_DIFF(cg.dischtime, cg.admittime, DAY) AS los_days
  FROM cohort_groups cg
  CROSS JOIN top_quartile_threshold t
  WHERE cg.med_score >= t.q3_value
),
part_b AS (
  SELECT 
    COUNT(*) AS n_patients,
    AVG(los_days) AS avg_los,
    SUM(hospital_expire_flag) AS n_deaths,
    ROUND(SUM(hospital_expire_flag) / COUNT(*), 4) AS mortality_rate
  FROM top_quartile_patients
)

-- Combined final results
SELECT 
  'part_a' AS part,
  group_flag,
  n_patients,
  min_score,
  max_score,
  avg_score,
  quartiles,
  NULL AS n_patients_b,
  NULL AS avg_los,
  NULL AS n_deaths,
  NULL AS mortality_rate
FROM part_a
UNION ALL
SELECT 
  'part_b' AS part,
  NULL AS group_flag,
  NULL AS n_patients,
  NULL AS min_score,
  NULL AS max_score,
  NULL AS avg_score,
  NULL AS quartiles,
  n_patients AS n_patients_b,
  avg_los,
  n_deaths,
  mortality_rate
FROM part_b;