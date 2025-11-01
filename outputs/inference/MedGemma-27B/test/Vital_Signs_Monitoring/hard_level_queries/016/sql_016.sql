WITH PatientDemographics AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age AS age,
    p.dod AS death_date
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
),
ICUStays AS (
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    ic.intime,
    ic.outtime,
    ic.los,
    ic.first_careunit,
    ic.last_careunit
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS ic
),
TransplantStatus AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    CASE
      WHEN di.icd_code LIKE 'Z94%' THEN 1
      ELSE 0
    END AS is_transplant
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a ON di.hadm_id = a.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p ON a.subject_id = p.subject_id
  WHERE
    di.icd_version = '10'
    AND di.seq_num = 1
    AND di.icd_code LIKE 'Z94%'
  GROUP BY
    p.subject_id,
    p.hadm_id
),
VitalSigns AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.itemid,
    ce.value AS value,
    ce.valuenum AS valuenum,
    ce.valueuom AS valueuom
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
  WHERE
    ce.itemid IN (8480, 8481, 8482, 8483, 8484, 8485, 8486, 8487, 8488, 8489, 8490, 8491, 8492, 8493, 8494, 8495, 8496, 8497, 8498, 8499, 8500, 8501, 8502, 8503, 8504, 8505, 8506, 8507, 8508, 8509, 8510, 8511, 8512, 8513, 8514, 8515, 8516, 85;