WITH first_icustays AS (
  -- Identify first ICU stay per patient admission
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime
  FROM (
    SELECT
      subject_id,
      hadm_id,
      stay_id,
      intime,
      ROW_NUMBER() OVER(PARTITION BY subject_id, hadm_id ORDER BY intime) AS rn
    FROM
      `physionet-data.mimiciv_3_1_icu.icustays`
  )
  WHERE rn = 1
),

ards_admissions AS (
  -- Admissions with ARDS diagnosis
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
      AND d.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) LIKE '%acute respiratory distress%'
),

patient_metrics AS (
  -- Per-patient metrics for their first ICU stay
  SELECT
    f.subject_id,
    f.hadm_id,
    p.gender,
    p.anchor_age,
    -- Flag for female ARDS cohort aged 37-47
    IF(
      p.gender = 'F'
      AND p.anchor_age BETWEEN 37 AND 47
      AND a.hadm_id IS NOT NULL,
      1,
      0
    ) AS is_ards_female_37_47,
    -- Count distinct procedures in first 72h of ICU
    COALESCE(proc.procedure_count, 0) AS procedure_count,
    -- Hospital LOS in days
    TIMESTAMP_DIFF(ad.dischtime, ad.admittime, DAY) AS hospital_los,
    ad.hospital_expire_flag
  FROM
    first_icustays f
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON f.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` ad
      ON f.subject_id = ad.subject_id
      AND f.hadm_id = ad.hadm_id
    LEFT JOIN ards_admissions a
      ON f.subject_id = a.subject_id
      AND f.hadm_id = a.hadm_id
    LEFT JOIN (
      -- Compute procedure counts within 72h
      SELECT
        pr.subject_id,
        pr.hadm_id,
        COUNT(DISTINCT pr.icd_code) AS procedure_count
      FROM
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
        JOIN first_icustays fi
          ON pr.subject_id = fi.subject_id
          AND pr.hadm_id = fi.hadm_id
      WHERE
        DATE(pr.chartdate) <= DATE_ADD(DATE(fi.intime), INTERVAL 3 DAY)
      GROUP BY
        pr.subject_id,
        pr.hadm_id
    ) proc
      ON f.subject_id = proc.subject_id
      AND f.hadm_id = proc.hadm_id
),

aggregated AS (
  -- Aggregate statistics for both cohorts
  SELECT
    cohort_label,
    APPROX_QUANTILES(procedure_count, 100)[OFFSET(75)] AS p75_procedure_count,
    APPROX_QUANTILES(procedure_count, 100)[OFFSET(90)] AS p90_procedure_count,
    ROUND(AVG(hospital_los), 2) AS mean_hospital_los,
    ROUND(AVG(hospital_expire_flag), 4) AS in_hospital_mortality_rate
  FROM (
    -- ARDS female 37-47 cohort
    SELECT
      'ARDS_Female_37_47' AS cohort_label,
      procedure_count,
      hospital_los,
      hospital_expire_flag
    FROM
      patient_metrics
    WHERE
      is_ards_female_37_47 = 1

    UNION ALL

    -- All ICU first-stay patients
    SELECT
      'All_ICU_First_Stays' AS cohort_label,
      procedure_count,
      hospital_los,
      hospital_expire_flag
    FROM
      patient_metrics
  )
  GROUP BY
    cohort_label
)

SELECT *
FROM aggregated
ORDER BY cohort_label;