WITH patients_filtered AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients
  WHERE gender = 'M'
    AND anchor_age >= 39
    AND anchor_age <= 49
),
admissions_filtered AS (
  SELECT hadm_id, subject_id, admittime, dischtime, hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions
  WHERE subject_id IN (SELECT subject_id FROM patients_filtered)
),
prescriptions_24h AS (
  SELECT p.hadm_id, LOWER(p.drug) AS drug
  FROM `physionet-data.mimiciv_3_1_hosp`.prescriptions p
  INNER JOIN admissions_filtered a
    ON p.hadm_id = a.hadm_id
  WHERE p.starttime >= a.admittime
    AND p.starttime < DATETIME_ADD(a.admittime, INTERVAL 24 HOUR)
),
drug_classification AS (
  SELECT 
    hadm_id,
    drug,
    CASE
      WHEN drug IN ('haloperidol', 'ondansetron', 'moxifloxacin', 'methadone', 'amiodarone')
        THEN 1 ELSE 0
    END AS is_qt_drug,
    CASE
      WHEN drug IN ('warfarin', 'heparin', 'enoxaparin', 'clopidogrel', 'aspirin', 'apixaban', 'rivaroxaban')
        THEN 1 ELSE 0
    END AS is_bleeding_drug
  FROM prescriptions_24h
),
hadm_drug_flags AS (
  SELECT hadm_id,
    MAX(is_qt_drug) AS has_qt_drug,
    MAX(is_bleeding_drug) AS has_bleeding_drug,
    COUNT(DISTINCT drug) AS med_count
  FROM drug_classification
  GROUP BY hadm_id
),
group_with_percentile AS (
  SELECT 
    'QT-prolonging' AS risk_group,
    med_count,
    dischtime,
    admittime,
    hospital_expire_flag,
    PERCENT_RANK() OVER (ORDER BY med_count) AS complexity_percentile
  FROM hadm_drug_flags h
  INNER JOIN admissions_filtered a ON h.hadm_id = a.hadm_id
  WHERE h.has_qt_drug = 1

  UNION ALL

  SELECT 
    'Bleeding-risk' AS risk_group,
    med_count,
    dischtime,
    admittime,
    hospital_expire_flag,
    PERCENT_RANK() OVER (ORDER BY med_count) AS complexity_percentile
  FROM hadm_drug_flags h
  INNER JOIN admissions_filtered a ON h.hadm_id = a.hadm_id
  WHERE h.has_bleeding_drug = 1
)
SELECT
  risk_group,
  AVG(DATETIME_DIFF(dischtime, admittime, SECOND) / (24 * 3600)) AS avg_los_days,
  AVG(hospital_expire_flag) AS mortality_rate
FROM group_with_percentile
WHERE complexity_percentile >= 0.75
GROUP BY risk_group
ORDER BY risk_group;