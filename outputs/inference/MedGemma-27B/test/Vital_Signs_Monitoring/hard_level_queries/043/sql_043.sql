WITH RespiratoryFailurePatients AS (
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    ic.intime,
    ic.outtime,
    ic.los,
    h.gender,
    h.anchor_age,
    h.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS ic
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS h
    ON ic.hadm_id = h.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON ic.hadm_id = d.hadm_id
  WHERE
    h.gender = 'M'
    AND h.anchor_age BETWEEN 40 AND 50
    AND d.icd_code IN ('J81', 'J82', 'R09.2', 'R06.02', 'R06.00', 'R06.01', 'R06.03', 'R06.09', 'R09.89') -- Respiratory failure codes
    AND ic.intime BETWEEN TIMESTAMP_SUB(ic.intime, INTERVAL 48 HOUR) AND ic.intime -- Ensure patient is in ICU for at least 48 hours
),
VitalInstabilityIndex AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    charttime,
    valuenum AS vii
  FROM `physionet-data.mimiciv_3_1_icu.chartevents`
  WHERE
    itemid = 220187 -- Vital Instability Index
),
HypotensionBurden AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    charttime,
    valuenum AS map
  FROM `physionet-data.mimiciv_3_1_icu.chartevents`
  WHERE
    itemid = 455 -- Mean Arterial Pressure
),
TachycardiaBurden AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    charttime,
    valuenum AS hr
  FROM `physionet-data.mimiciv_3_1_icu.chartevents`
  WHERE
    itemid = 220176 -- Heart Rate
)
SELECT
  -- Calculate SD and percentiles of Vii
  STDDEV(vii) AS vii_sd,
  APPROX_QUANTILES(vii, [0.25, 0.5, 0.75, 0.95]) AS vii_percentiles,
  -- Calculate Hypotension Burden
  SUM(CASE WHEN map < 65 THEN 1 ELSE 0 END) AS hypotension_burden,
  -- Calculate Tachycardia Burden
  SUM(CASE WHEN hr > 100 THEN 1 ELSE 0 END) AS tachycardia_burden,
  -- Calculate ICU LOS
  AVG(los) AS avg_icu_los,
  -- Calculate Mortality
  AVG(hospital_expire_flag) AS mortality
FROM RespiratoryFailurePatients
JOIN VitalInstabilityIndex ON RespiratoryFailurePatients.subject_id = VitalInstabilityIndex.subject_id AND RespiratoryFailurePatients.hadm_id = VitalInstabilityIndex.hadm_id AND RespiratoryFailurePatients.stay_id = VitalInstabilityIndex.stay_id
JOIN HypotensionBurden ON RespiratoryFailurePatients.subject_id = HypotensionBurden.subject_id AND RespiratoryFailurePatients.hadm_id = HypotensionBurden.hadm_id AND RespiratoryFailurePatients.stay_id = HypotensionBurden.stay_id
JOIN TachycardiaBurden ON RespiratoryFailurePatients.subject_id = TachycardiaBurden.subject_id AND RespiratoryFailurePatients.hadm_id = TachycardiaBurden.hadm_id AND RespiratoryFailurePatients.stay_id = TachycardiaBurden.stay_id
WHERE
  charttime BETWEEN intime AND TIMESTAMP_SUB(intime, INTERVAL 48 HOUR) -- Filter for first 48 hours
GROUP BY
  subject_id,
  hadm_id,
  stay_id
ORDER BY
  subject_id,
  hadm_id,
  stay;