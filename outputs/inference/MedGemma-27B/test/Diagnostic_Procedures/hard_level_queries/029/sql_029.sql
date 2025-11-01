WITH PatientCohort AS (
  -- Select patients meeting the initial criteria: male, age 68-78, ICU stay, received vasopressors within 72 hours
  SELECT DISTINCT
    p.subject_id,
    p.gender,
    p.anchor_age,
    ic.stay_id,
    ic.intime,
    ic.outtime,
    ic.los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS ic
    ON p.subject_id = ic.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    AND EXISTS (
      -- Check for vasopressor administration within 72 hours of ICU admission
      SELECT
        1
      FROM `physionet-data.mimiciv_3_1_icu.inputevents` AS ie
      JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
        ON ie.itemid = di.itemid
      WHERE
        ie.subject_id = p.subject_id
        AND ie.stay_id = ic.stay_id
        AND ie.starttime BETWEEN ic.intime AND TIMESTAMP_ADD(ic.intime, INTERVAL 72 HOUR)
        AND di.label IN ('norepinephrine', 'epinephrine', 'dopamine', 'vasopressin') -- Common vasopressors
    )
), DiagnosticLoad AS (
  -- Calculate the diagnostic load (labs + imaging) for each patient within 72 hours of ICU admission
  SELECT
    pc.subject_id,
    pc.stay_id,
    COUNT(DISTINCT ce.itemid) AS diagnostic_load
  FROM PatientCohort AS pc
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON pc.subject_id = ce.subject_id AND pc.stay_id = ce.stay_id
    AND ce.charttime BETWEEN pc.intime AND TIMESTAMP_ADD(pc.intime, INTERVAL 72 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
    AND di.category = 'Laboratory'
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.hcpcsevents` AS he
    ON pc.subject_id = he.subject_id
    AND he.chartdate BETWEEN pc.intime AND TIMESTAMP_ADD(pc.intime, INTERVAL 72 HOUR)
    AND he.hcpcs_cd LIKE '7%' -- HCPCS codes starting with 7 often represent imaging
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` AS dh
    ON he.hcpcs_cd = dh.code
    AND dh.category = 'Imaging'
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di_diag
    ON pc.subject_id = di_diag.subject_id
    AND di_;