with `icustays` and `chartevents` to calculate the vital sign instability score for the first 72 hours of the ICU stay.

**Step 6: Calculate Percentile, ICU LOS, and Mortality**
Calculate the percentile of the instability score, ICU LOS, and mortality for the top instability quartile.

**Step 7: Final Review**
Review the complete query for correctness, ensuring all joins are correct, filters are applied appropriately, and the final calculations (percentile, LOS, mortality) are accurate. Ensure the query uses the correct table names and column names from the MIMIC-IV schema.

sql
WITH PatientInfo AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M' AND p.anchor_age BETWEEN 84 AND 94
), DiagnosisInfo AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    d.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    di.long_title LIKE '%ischemic stroke%'
), ICUStayInfo AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    i.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
  JOIN PatientInfo AS pi
    ON i.subject_id = pi.subject_id AND i.hadm_id = pi.hadm_id
  JOIN DiagnosisInfo AS di
    ON i.subject_id = di.subject_id AND i.hadm_id = di.hadm_id
), VitalSignInstability AS (
  SELECT
    isi.subject_id,
    isi.hadm_id,
    isi.stay_id,
    SUM(CASE
      WHEN ce.itemid IN (455, 448, 466, 509) THEN
        CASE
          WHEN ce.valuenum > 140 THEN 1
          WHEN ce.valuenum < 60 THEN 1
          ELSE 0
        END
      WHEN ce.itemid IN (456, 457) THEN
        CASE;