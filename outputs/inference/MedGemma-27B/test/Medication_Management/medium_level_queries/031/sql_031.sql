WITH PatientCohort AS (
  SELECT DISTINCT
    p.subject_id,
    p.gender,
    p.anchor_age,
    -- Check for diabetes diagnosis (ICD-10 codes)
    CASE
      WHEN EXISTS (
        SELECT
          1
        FROM
          `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
        WHERE
          d.subject_id = p.subject_id
          AND d.icd_code LIKE 'E10%' -- Diabetes mellitus
          OR d.icd_code LIKE 'E11%' -- Type 2 diabetes mellitus
          OR d.icd_code LIKE 'E13%' -- Other specified diabetes mellitus
          OR d.icd_code LIKE 'E14%' -- Diabetes mellitus without complications
      ) THEN 1
      ELSE 0
    END AS has_diabetes,
    -- Check for heart failure diagnosis (ICD-10 codes)
    CASE
      WHEN EXISTS (
        SELECT
          1
        FROM
          `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
        WHERE
          d.subject_id = p.subject_id
          AND d.icd_code LIKE 'I50%' -- Heart failure
          OR d.icd_code LIKE 'I11%' -- Hypertensive heart and chronic kidney disease with heart failure
          OR d.icd_code LIKE 'I13%' -- Hypertensive heart disease with heart failure
      ) THEN 1
      ELSE 0
    END AS has_heart_failure
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.gender = 'M' AND p.anchor_age BETWEEN 53 AND 63
),
MedicationEvents AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.charttime,
    -- Filter for injectable GLP-1 RA medications
    CASE
      WHEN LOWER(p.medication) LIKE '%semaglutide%' OR LOWER(p.medication) LIKE '%liraglutide%' OR LOWER(p.medication) LIKE '%exenatide%' OR LOWER(p.medication) LIKE '%dulaglutide%' THEN 1
      ELSE 0
    END AS is_glp1_ra,
    -- Check if the medication is injectable (based on route)
    CASE
      WHEN LOWER(p.route) LIKE '%subq%' OR LOWER(p.route) LIKE '%injection%' OR LOWER(p.route) LIKE '%sq%' THEN 1
      ELSE 0
    END AS is_injectable
  FROM
    `physionet-data.mimiciv_3_1_hosp.emar` AS p
  WHERE
    p.medication IS NOT NULL AND p.route IS NOT NULL
),
AdmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
)
SELECT
  COUNT(CASE WHEN me.charttime BETWEEN ai.admittime AND TIMESTAMP_ADD(ai.admittime, INTERVAL 24 HOUR) THEN 1 ELSE NULL END) AS first_24_hours_count,
  COUNT(CASE WHEN me.charttime BETWEEN TIMESTAMP_SUB(ai.dischtime, INTERVAL 12 HOUR) AND ai.dischtime THEN 1 ELSE NULL END) AS final_12_hours_count,
  COUNT(me.subject_id) AS total_count
FROM
  PatientCohort AS pc
JOIN
  AdmissionInfo AS ai ON pc.subject_id = ai.subject_id
JOIN
  MedicationEvents AS me ON pc.subject_id = me.subject_id AND ai.hadm_id = me.hadm_id
WHERE
  pc.has_diabetes = 1 AND pc.has_heart_failure = 1 AND me.is_glp1_ra = 1 AND me.is_injectable = 1;