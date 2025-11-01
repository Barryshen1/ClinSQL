WITH
    patient_admissions AS (
      -- Select relevant female patients aged 50-60 at admission
      SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
        p.gender,
        EXTRACT(YEAR FROM adm.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
      FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
      JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON adm.subject_id = p.subject_id
      WHERE
        p.gender = 'F'
        AND EXTRACT(YEAR FROM adm.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 50 AND 60
    ),
    acs_admissions AS (
      -- Identify admissions with primary or secondary ACS diagnoses
      SELECT
        pa.subject_id,
        pa.hadm_id,
        pa.admittime,
        pa.dischtime,
        pa.los_days,
        MAX(
          CASE
            WHEN
              di.seq_num = 1
              AND (
                (di.icd_version = 10 AND di.icd_code BETWEEN 'I20' AND 'I25')
                OR (di.icd_version = 9 AND di.icd_code BETWEEN '410' AND '414')
              )
            THEN 1
            ELSE 0
          END
        ) AS has_primary_acs_diag,
        MAX(
          CASE
            WHEN
              di.seq_num > 1
              AND (
                (di.icd_version = 10 AND di.icd_code BETWEEN 'I20' AND 'I25')
                OR (di.icd_version = 9 AND di.icd_code BETWEEN '410' AND '414')
              )
            THEN 1
            ELSE 0
          END
        ) AS has_secondary_acs_diag
      FROM
        patient_admissions AS pa
      JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
        ON pa.subject_id = di.subject_id AND pa.hadm_id = di.hadm_id
      GROUP BY
        pa.subject_id,
        pa.hadm_id,
        pa.admittime,
        pa.dischtime,
        pa.los_days
      HAVING
        -- Ensure at least one ACS diagnosis exists for the admission
        MAX(
          CASE
            WHEN
              (
                (di.icd_version = 10 AND di.icd_code BETWEEN 'I20' AND 'I25')
                OR (di.icd_version = 9 AND di.icd_code BETWEEN '410' AND '414')
              )
            THEN 1
            ELSE 0
          END
        ) = 1
    ),
    categorized_acs_admissions AS (
      -- Assign ACS diagnosis type and LOS category
      SELECT
        subject_id,
        hadm_id,
        los_days,
        CASE
          WHEN has_primary_acs_diag = 1 THEN 'Primary ACS'
          WHEN has_primary_acs_diag = 0 AND has_secondary_acs_diag = 1 THEN 'Secondary ACS'
          ELSE NULL -- This case should ideally not happen due to HAVING clause in acs_admissions
        END AS acs_diagnosis_type,
        CASE
          WHEN los_days BETWEEN 1 AND 4 THEN '1-4 Days'
          WHEN los_days BETWEEN 5 AND 8 THEN '5-8 Days'
          ELSE 'Other LOS'
        END AS los_category
      FROM
        acs_admissions
      WHERE
        (has_primary_acs_diag = 1) OR (has_primary_acs_diag = 0 AND has_secondary_acs_diag = 1)
    ),
    procedures_per_admission AS (
      -- Count diagnostic procedures for each relevant admission
      SELECT
        ca.subject_id,
        ca.hadm_id,
        ca.acs_diagnosis_type,
        ca.los_category,
        COUNT(proc_icd.hadm_id) AS num_diagnostic_procedures -- Count all procedures for the admission
      FROM
        categorized_acs_admissions AS ca
      JOIN
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc_icd
        ON ca.subject_id = proc_icd.subject_id AND ca.hadm_id = proc_icd.hadm_id
      WHERE
        ca.los_category IN ('1-4 Days', '5-8 Days') -- Filter to specified LOS categories
      GROUP BY
        ca.subject_id,
        ca.hadm_id,
        ca.acs_diagnosis_type,
        ca.los_category
    )
SELECT
  ppa.los_category,
  ppa.acs_diagnosis_type,
  -- Calculate p25, p50, p75 using APPROX_QUANTILES for aggregated percentiles
  APPROX_QUANTILES(ppa.num_diagnostic_procedures, 100)[OFFSET(25)] AS p25_diagnostic_procedures,
  APPROX_QUANTILES(ppa.num_diagnostic_procedures, 100)[OFFSET(50)] AS p50_diagnostic_procedures,
  APPROX_QUANTILES(ppa.num_diagnostic_procedures, 100)[OFFSET(75)] AS p75_diagnostic_procedures
FROM
  procedures_per_admission AS ppa
GROUP BY
  ppa.los_category,
  ppa.acs_diagnosis_type
ORDER BY
  ppa.los_category,
  ppa.acs_diagnosis_type;