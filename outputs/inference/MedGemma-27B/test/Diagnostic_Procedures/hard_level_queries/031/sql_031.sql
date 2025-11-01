WITH PatientCohort AS (
  -- Select patients meeting the criteria: male, age 66-76, HHS diagnosis
  SELECT DISTINCT
    p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON p.subject_id = di.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 66 AND 76
    AND di.icd_code = '250.2' -- HHS ICD-10 code
),
ICUStays AS (
  -- Select ICU stays for the identified patients
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    ic.intime,
    ic.outtime,
    a.hospital_expire_flag,
    a.dischtime,
    a.los -- Added hospital LOS
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS ic
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON ic.hadm_id = a.hadm_id
  WHERE
    ic.subject_id IN (
      SELECT
        subject_id
      FROM PatientCohort
    )
),
ProcedureCounts AS (
  -- Count procedures within 48 hours of ICU admission
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    COUNT(pe.itemid) AS procedure_count
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS ic
  JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
    ON ic.stay_id = pe.stay_id
  WHERE
    pe.starttime BETWEEN ic.intime AND TIMESTAMP_ADD(ic.intime, INTERVAL 48 HOUR)
  GROUP BY
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id
),
ProcedureBurdenQuintiles AS (
  -- Stratify ICU stays into quintiles based on procedure count
  SELECT
    pc.subject_id,
    pc.hadm_id,
    pc.stay_id,
    pc.procedure_count,
    NTILE(5) OVER (ORDER BY pc.procedure_count) AS procedure_quintile
  FROM ProcedureCounts AS pc
),
Readmissions AS (
  -- Calculate 30-day readmission status
  SELECT
    a.subject_id,
    a.hadm_id,
    CASE
      WHEN EXISTS (
        SELECT
          1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a2
        WHERE
          a2.subject_id = a.subject_id
          AND a2.admittime > TIMESTAMP_ADD(a.dischtime, INTERVAL 30 DAY)
      ) THEN 1
      ELSE 0
    END AS readmitted_30_day
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a -- Corrected table reference
  WHERE
    a.subject_id IN (
      SELECT
        subject_id
      FROM PatientCohort
    )
),
FinalResults AS (
  -- Combine all information and calculate final metrics
  SELECT
    pbq.procedure_quintile,
    COUNT(DISTINCT pbq.stay_id) AS num_icu_stays,
    AVG(pbq.procedure_count) AS mean_procedures,
    MIN(pbq.procedure_count) AS min_procedures,
    MAX(pbq.procedure_count) AS max_procedures,
    AVG(CASE WHEN ic.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS hospital_mortality_percent,
    AVG(a.los) AS mean_hospital_los,
    AVG(r.readmitted_30_day) AS readmission_percent
  FROM ProcedureBurdenQuintiles AS pbq
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS ic;