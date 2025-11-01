WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    -- Compute age at admission: anchor_age + (admission year - anchor_year)
    p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age,
    -- Flag for HHS: if any diagnosis_icd has icd_code in ('E10.21','E11.21') and icd_version=10
    CASE WHEN d.icd_code IN ('E10.21', 'E11.21') AND d.icd_version = 10 THEN 1 ELSE 0 END AS hhs_status,
    -- ICU LOS in hours
    TIMESTAMP_DIFF(i.outtime, i.intime, HOUR) AS los,
    -- Mortality within 48 hours of ICU admission: if deathtime is within 48 hours of intime
    CASE WHEN a.deathtime IS NOT NULL 
         AND TIMESTAMP_DIFF(a.deathtime, i.intime, HOUR) <= 48 
         THEN 1 ELSE 0 END AS mortality
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
    AND d.icd_version = 10
    AND d.icd_code IN ('E10.21', 'E11.21')
  WHERE
    -- Age between 78 and 88 at admission
    p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 78 AND 88
    AND p.gender = 'M'
),
-- Placeholder for parameter mapping and abnormal event detection (simplified for example)
-- In practice, this CTE would map itemids to parameters and define abnormality conditions
-- and then join with chartevents, labevents, etc., to create a unified view of abnormal events
all_abnormal_events AS (
  -- This is a simplified example; full implementation requires detailed mapping
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    charttime,
    'example_parameter' AS parameter,
    1 AS is_abnormal  -- Placeholder; actual condition would be applied here
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents`
  WHERE
    itemid IN (211, 220045)  -- Example itemids for heart rate
    AND valuenum > 100  -- Example condition
  UNION ALL
  -- Additional unions for other parameters and tables (labevents, etc.)
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    charttime,
    'another_parameter' AS parameter,
    1 AS is_abnormal
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents`
  WHERE
    itemid IN (50809)  -- Example itemid for lactate
    AND valuenum > 2
),
cis_burden AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.hhs_status,
    -- CIS: count distinct parameters that were abnormal at least once in first 48 hours
    COUNT(DISTINCT CASE WHEN a.parameter IS NOT NULL THEN a.parameter END) AS cis,
    -- Total abnormal events in first 48 hours
    COUNT(CASE WHEN a.is_abnormal = 1 THEN 1 END) AS total_abnormal_events,
    c.los,
    c.mortality
  FROM
    cohort c
  LEFT JOIN
    all_abnormal_events a
    ON c.subject_id = a.subject_id
    AND c.stay_id = a.stay_id
    AND a.charttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 48 HOUR)
  GROUP BY
    c.subject_id, c.hadm_id, c.stay_id, c.hhs_status, c.los, c.mortality
)
SELECT
  hhs_status,
  -- Compute percentiles for CIS, burden, and LOS
  APPROX_QUANTILES(cis, 100)[OFFSET(25)] AS cis_25,
  APPROX_QUANTILES(cis, 100)[OFFSET(50)] AS cis_50,
  APPROX_QUANTILES(cis, 100)[OFFSET(75)] AS cis_75,
  APPROX_QUANTILES(total_abnormal_events / 48.0, 100)[OFFSET(25)] AS burden_25,
  APPROX_QUANTILES(total_abnormal_events / 48.0, 100)[OFFSET(50)] AS burden_50,
  APPROX_QUANTILES(total_abnormal_events / 48.0, 100)[OFFSET(75)] AS burden_75,
  APPROX_QUANTILES(los, 100)[OFFSET(25)] AS los_25,
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS los_50,
  APPROX_QUANTILES(los, 100)[OFFSET(75)] AS los_75,
  -- Mortality rate (proportion)
  AVG(mortality) AS mortality_rate
FROM
  cis_burden
GROUP BY
  hhs_status
ORDER BY
  hhs_status;