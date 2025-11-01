WITH PatientCohort AS (
  -- Select patients matching the criteria: male, age 44, status epilepticus diagnosis
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.hadm_id,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age = 44
    AND a.admission_type = 'EMERGENCY' -- Assuming status epilepticus is an emergency admission
    AND EXISTS (
      SELECT
        1
      FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      WHERE
        d.subject_id = p.subject_id
        AND d.hadm_id = a.hadm_id
        AND d.icd_code = 'R56.9' -- ICD-9 code for seizure disorder, unspecified (adjust if needed)
    )
),

MedicationInteractions AS (
  -- Identify medications with QT-prolonging or bleeding risk
  SELECT
    e.subject_id,
    e.hadm_id,
    e.charttime,
    CASE
      WHEN e.medication IN ('Amiodarone', 'Sotalol', 'Dofetilide', 'Ibutilide', 'Quinidine', 'Procainamide', 'Disopyramide', 'Diltiazem', 'Verapamil', 'Methadone', 'Macrolides', 'Fluconazole', 'Ketoconazole', 'Erythromycin', 'Azithromycin', 'Chloroquine', 'Hydroxychloroquine', 'Ondansetron', 'Haloperidol', 'Risperidone', 'Ziprasidone', 'Levofloxacin', 'Moxifloxacin', 'Ciprofloxacin', 'Linezolid', 'Pentamidine', 'Trimethoprim-Sulfamethoxazole') THEN 'QT-prolonging'
      WHEN e.medication IN ('Warfarin', 'Heparin', 'Enoxaparin', 'Dalteparin', 'Apixaban', 'Rivaroxaban', 'Edoxaban', 'Dabigatran', 'Aspirin', 'Clopidogrel', 'Prasugrel', 'Ticagrelor', 'NSAIDs', 'SSRIs', 'SNRIs', 'TCAs', 'MAOIs', 'Amiodarone', 'Sotalol', 'Dofetilide', 'Ibutilide', 'Quinidine', 'Procainamide', 'Disopyramide', 'Diltiazem', 'Verapamil', 'Methadone', 'Macrolides', 'Fluconazole', 'Ketoconazole', 'Erythromycin', 'Azithromycin', 'Chloroquine', 'Hydroxychloroquine', 'Ondansetron', 'Haloperidol', 'Risperidone', 'Ziprasidone', 'Levofloxacin', 'Moxifloxacin', 'Ciprofloxacin', 'Linezolid', 'Pentamidine', 'Trimethoprim-Sulfamethoxazole') THEN 'Bleeding-risk'
      ELSE 'None'
    END AS interaction_type
  FROM
    `physionet-data.mimiciv_3_1_hosp.emar` AS e
  WHERE
    e.subject_id IN (SELECT subject_id FROM PatientCohort)
    AND e.charttime BETWEEN (SELECT admittime FROM PatientCohort WHERE subject_id = e.subject_id) AND TIMESTAMP_ADD((SELECT admittime FROM PatientCohort WHERE subject_id = e.subject_id), INTERVAL 24 HOUR)
),

MedicationComplexity AS (
  SELECT
    subject_id,
    hadm_id,
    COUNT(DISTINCT medication) AS distinct_meds
  FROM
    MedicationInteractions
  WHERE
    interaction_type != 'None'
  GROUP BY
    subject_id,
    hadm_id
),

LOS AS (
  SELECT
    subject_id,
    hadm_id,
    (TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24) AS los;