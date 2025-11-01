WITH AKI_Patients AS (
  -- Identify patients with AKI based on ICD-9 codes
  SELECT DISTINCT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 47 AND 57
    AND d.icd_code IN ('585', '586', '587', '588', '589', 'N17.9') -- AKI ICD-9 codes
),
Control_Patients AS (
  -- Identify age-matched male controls without AKI
  SELECT DISTINCT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 47 AND 57
    AND d.icd_code NOT IN ('585', '586', '587', '588', '589', 'N17.9') -- Exclude AKI ICD-9 codes
),
Lab_Instability_Score AS (
  -- Calculate the 72-hour laboratory instability score
  SELECT
    a.hadm_id,
    AVG(lab_instability_score) AS mean_lab_instability_score
  FROM (
    SELECT
      a.hadm_id,
      SUM(CASE
        WHEN ABS(l1.valuenum - l2.valuenum) > 0.5 THEN 1
        ELSE 0
      END) AS lab_instability_score
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS l1
      ON a.hadm_id = l1.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS l2
      ON a.hadm_id = l2.hadm_id
      AND l1.itemid = l2.itemid
      AND l1.charttime + INTERVAL '1' HOUR = l2.charttime
    WHERE
      l1.itemid IN (SELECT itemid FROM `physionet-data.mimiciv_3_1_hosp.d_labitems` WHERE category = 'Chemistry') -- Specify the lab category
    GROUP BY
      a.hadm_id
  )
  GROUP BY
    a.hadm_id
),
Critical_Events AS (
  -- Calculate critical events (e.g., intubation, vasopressors)
  SELECT
    a.hadm_id,
    COUNT(DISTINCT ce.itemid) AS critical_event_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.chartevents` AS ce
    ON a.hadm_id = ce.hadm_id
  WHERE
    ce.itemid IN (SELECT itemid FROM `physionet-data.mimiciv_3_1_hosp.d_items` WHERE label IN ('Intubation', 'Vasopressor')) -- Specify critical event items
  GROUP BY;