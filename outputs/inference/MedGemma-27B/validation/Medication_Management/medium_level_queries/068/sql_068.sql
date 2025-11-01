WITH PatientCohort AS (
  -- Identify patients meeting the criteria: 83-93 years old, female, with T2DM and HF
  SELECT
    p.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 83 AND 93 -- Corrected age range
    AND d.icd_code IN ('E11.9', 'E11.2', 'E11.3', 'E11.4', 'E11.5', 'E11.6', 'E11.7', 'E11.8', 'E11.0', 'E11.1') -- T2DM codes
    AND d.icd_code IN ('I50.9', 'I50.1', 'I50.2', 'I50.3', 'I50.4', 'I50.6', 'I50.8', 'I50.0', 'I50.5', 'I50.7') -- HF codes
  GROUP BY
    p.subject_id
  HAVING
    COUNT(DISTINCT d.icd_code) >= 2 -- Ensure both T2DM and HF are present
),

InsulinOrders AS (
  -- Identify insulin orders within the first 48 hours of admission
  SELECT
    p.subject_id,
    p.hadm_id,
    p.admittime,
    p.dischtime,
    p.deathtime,
    p.hospital_expire_flag,
    pr.drug AS insulin_drug,
    pr.route AS insulin_route,
    pr.starttime,
    pr.stoptime,
    pr.dose_val_rx,
    pr.dose_unit_rx,
    pr.frequency,
    pr.doses_per_24_hrs,
    pr.duration,
    pr.duration_interval,
    CASE
      WHEN pr.route = 'SubQ' THEN 'basal'
      WHEN pr.route = 'IV' THEN 'bolus'
      WHEN pr.route = 'SubQ' AND pr.frequency LIKE '%daily%' THEN 'basal'
      WHEN pr.route = 'IV' AND pr.frequency LIKE '%daily%' THEN 'bolus'
      WHEN pr.route = 'SubQ' AND pr.frequency LIKE '%twice daily%' THEN 'basal-bolus'
      WHEN pr.route = 'IV' AND pr.frequency LIKE '%twice daily%' THEN 'basal-bolus'
      WHEN pr.route = 'SubQ' AND pr.frequency LIKE '%sliding scale%' THEN 'sliding-scale'
      WHEN pr.route = 'IV' AND pr.frequency LIKE '%sliding scale%' THEN 'sliding-scale'
      ELSE 'other'
    END AS insulin_type,
    -- Determine if the order is initiated within the first 48 hours
    CASE
      WHEN TIMESTAMP_DIFF(pr.starttime, p.admittime, HOUR) BETWEEN 0 AND 48 THEN 'First 48h'
      WHEN TIMESTAMP_DIFF(pr.starttime, p.admittime, HOUR) > 48 THEN 'Final 12h'
      ELSE 'Other'
    END AS time_window
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    ON a.hadm_id = pr.hadm_id
  WHERE
    p.subject_id IN (SELECT subject_id FROM PatientCohort)
    AND pr.drug LIKE '%insulin%'
    AND pr.drug NOT LIKE '%glargine%'
    AND pr.drug NOT LIKE '%detemir%'
    AND pr.drug NOT LIKE '%degludec%'
    AND pr.drug NOT LIKE '%lispro%'
    AND pr.drug NOT LIKE;