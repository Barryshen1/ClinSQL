WITH PatientDKA AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    d.long_title AS diagnosis
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
    ON di.icd_code = d.icd_code
    AND di.icd_version = d.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 84 AND 94
    AND d.long_title LIKE '%diabetic ketoacidosis%'
    AND di.seq_num = 1 -- Assuming primary diagnosis
), PatientICU AS (
  SELECT
    p.subject_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los
  FROM PatientDKA AS p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS i
    ON p.subject_id = i.subject_id
  WHERE
    i.intime BETWEEN p.admittime AND p.admittime + INTERVAL '48' HOUR
), MedicationComplexity AS (
  SELECT
    p.subject_id,
    COUNT(DISTINCT ph.drug) AS medication_complexity
  FROM PatientICU AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.pharmacy` AS ph
    ON p.subject_id = ph.subject_id
  WHERE
    ph.starttime BETWEEN p.intime AND p.intime + INTERVAL '48' HOUR
    AND ph.stoptime > p.intime -- Only count medications started during the first 48h
  GROUP BY
    p.subject_id
), HyperkalemiaRisk AS (
  SELECT
    p.subject_id
  FROM PatientICU AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.emar` AS e
    ON p.subject_id = e.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` AS ed
    ON e.emar_id = ed.emar_id
  WHERE
    e.charttime BETWEEN p.intime AND p.intime + INTERVAL '48' HOUR
    AND ed.medication IN ('Spironolactone', 'Eplerenone', 'Amiloride', 'Triamterene', 'Potassium Sparing Diuretic') -- List of hyperkalemia-risk drugs
  GROUP BY
    p.subject_id
)
SELECT
  CASE
    WHEN hr.subject_id IS NOT NULL THEN 'With Hyperkalemia Risk'
    ELSE 'Without Hyperkalemia Risk'
  END AS hyperkalemia_risk_status,
  AVG(mc.medication_complexity) AS avg_medication_complexity,
  PERCENTILE_CONT(mc.medication_complexity, 0.5) AS median_medication_complexity,
  AVG(icu.los) AS avg_los,
  AVG(CASE WHEN icu.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality,
  AVG(CASE WHEN mc.medication_complexity >= (SELECT PERCENTILE_CONT(medication_complexity, 0.75) FROM MedicationComplexity) THEN icu.los ELSE NULL END) AS los_top_complexity_quartile,
  AVG(CASE WHEN mc.medication_complexity >= (SELECT PERCENTILE_CONT(medication_complexity, 0.75) FROM MedicationComplexity) THEN CASE WHEN icu.hospital_expire_flag = 1 THEN 1 ELSE 0 END ELSE NULL END) AS mortality_top_complexity_quartile
FROM PatientICU AS;