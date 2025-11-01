WITH eligible_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS admission_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 74 AND 84
),
medications_first24 AS (
  SELECT 
    a.hadm_id,
    p.drug,
    p.starttime
  FROM eligible_admissions a
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON a.hadm_id = p.hadm_id
  WHERE p.starttime BETWEEN a.admittime AND a.admittime + INTERVAL '24' HOUR
),
qt_drugs AS (
  SELECT 'amiodarone' AS drug_name UNION ALL
  SELECT 'quinidine' UNION ALL
  SELECT 'sotalol' UNION ALL
  SELECT 'dofetilide' UNION ALL
  SELECT 'procainamide' UNION ALL
  SELECT 'cisapride' UNION ALL
  SELECT 'haloperidol' UNION ALL
  SELECT 'thioridazine' UNION ALL
  SELECT 'chlorpromazine' UNION ALL
  SELECT 'erythromycin' UNION ALL
  SELECT 'clarithromycin' UNION ALL
  SELECT 'ciprofloxacin' UNION ALL
  SELECT 'levofloxacin' UNION ALL
  SELECT 'moxifloxacin' UNION ALL
  SELECT 'fluconazole' UNION ALL
  SELECT 'ketoconazole' UNION ALL
  SELECT 'itraconazole' UNION ALL
  SELECT 'voriconazole' UNION ALL
  SELECT 'methadone' UNION ALL
  SELECT 'chloroquine' UNION ALL
  SELECT 'hydroxychloroquine' UNION ALL
  SELECT 'halofantrine' UNION ALL
  SELECT 'pentamidine' UNION ALL
  SELECT 'arsenic trioxide' UNION ALL
  SELECT 'tacrolimus' UNION ALL
  SELECT 'cyclosporine' UNION ALL
  SELECT 'diltiazem' UNION ALL
  SELECT 'verapamil' UNION ALL
  SELECT 'amlodipine' UNION ALL
  SELECT 'nifedipine' UNION ALL
  SELECT 'dronedarone' UNION ALL
  SELECT 'ibutilide' UNION ALL
  SELECT 'flecainide' UNION ALL
  SELECT 'propafenone' UNION ALL
  SELECT 'disopyramide' UNION ALL
  SELECT 'lidocaine' UNION ALL
  SELECT 'tocainide' UNION ALL
  SELECT 'mexiletine' UNION ALL
  SELECT 'prilocaine' UNION ALL
  SELECT 'bupivacaine' UNION ALL
  SELECT 'ropivacaine' UNION ALL
  SELECT 'levobupivacaine'
),
bleeding_drugs AS (
  SELECT 'warfarin' AS drug_name UNION ALL
  SELECT 'heparin' UNION ALL
  SELECT 'enoxaparin' UNION ALL
  SELECT 'dalteparin' UNION ALL
  SELECT 'tinzaparin' UNION ALL
  SELECT 'rivaroxaban' UNION ALL
  SELECT 'apixaban' UNION ALL
  SELECT 'dabigatran' UNION ALL
  SELECT 'edoxaban' UNION ALL
  SELECT 'ticagrelor' UNION ALL
  SELECT 'prasugrel' UNION ALL
  SELECT 'clopidogrel' UNION ALL
  SELECT 'aspirin' UNION ALL
  SELECT 'dipyridamole' UNION ALL
  SELECT 'ticlopidine' UNION ALL
  SELECT 'abciximab' UNION ALL
  SELECT 'eptifibatide' UNION ALL
  SELECT 'tirofiban' UNION ALL
  SELECT 'alteplase' UNION ALL
  SELECT 'reteplase' UNION ALL
  SELECT 'tenecteplase' UNION ALL
  SELECT 'urokinase' UNION ALL
  SELECT 'streptokinase' UNION ALL
  SELECT 'anistreplase' UNION ALL
  SELECT 'fondaparinux' UNION ALL
  SELECT 'bivalirudin' UNION ALL
  SELECT 'argatroban'
),
qt_flag AS (
  SELECT 
    m.hadm_id,
    MAX(CASE WHEN q.drug_name IS NOT NULL THEN 1 ELSE 0 END) AS has_qt_drug
  FROM medications_first24 m
  LEFT JOIN qt_drugs q ON m.drug = q.drug_name
  GROUP BY m.hadm_id
),
bleeding_flag AS (
  SELECT 
    m.hadm_id,
    MAX(CASE WHEN b.drug_name IS NOT NULL THEN 1 ELSE 0 END) AS has_bleeding_drug
  FROM medications_first24 m
  LEFT JOIN bleeding_drugs b ON m.drug = b.drug_name
  GROUP BY m.hadm_id
),
complexity AS (
  SELECT 
    m.hadm_id,
    COUNT(DISTINCT m.drug) AS medication_count
  FROM medications_first24 m
  GROUP BY m.hadm_id
),
icu_status AS (
  SELECT 
    a.hadm_id,
    MAX(CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END) AS in_icu
  FROM eligible_admissions a
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  GROUP BY a.hadm_id
),
los_mortality AS (
  SELECT 
    a.hadm_id,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los,
    a.hospital_expire_flag
  FROM eligible_admissions a
),
all_data AS (
  SELECT 
    c.hadm_id,
    c.medication_count,
    q.has_qt_drug,
    b.has_bleeding_drug,
    i.in_icu,
    l.los,
    l.hospital_expire_flag
  FROM complexity c
  LEFT JOIN qt_flag q ON c.hadm_id = q.hadm_id
  LEFT JOIN bleeding_flag b ON c.hadm_id = b.hadm_id
  LEFT JOIN icu_status i ON c.hadm_id = i.hadm_id
  LEFT JOIN los_mortality l ON c.hadm_id = l.hadm_id
),
los_percentile AS (
  SELECT PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY los) AS top_quartile_los
  FROM all_data
)
SELECT
  AVG(medication_count) AS mean_complexity,
  MIN(medication_count) AS min_complexity,
  MAX(medication_count) AS max_complexity,
  STDDEV(medication_count) AS std_dev_complexity,
  AVG(has_qt_drug) AS prevalence_qt,
  AVG(has_bleeding_drug) AS prevalence_bleeding,
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY medication_count) AS p25_complexity,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY medication_count) AS p50_complexity,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY medication_count) AS p75_complexity,
  AVG(CASE WHEN in_icu = 1 THEN medication_count ELSE NULL END) AS mean_complexity_icu,
  AVG(CASE WHEN in_icu = 0 THEN medication_count ELSE NULL END) AS mean_complexity_non_icu,
  (SELECT AVG(hospital_expire_flag) FROM all_data WHERE los >= (SELECT top_quartile_los FROM los_percentile)) AS mortality_top_quartile_los
FROM all_data;