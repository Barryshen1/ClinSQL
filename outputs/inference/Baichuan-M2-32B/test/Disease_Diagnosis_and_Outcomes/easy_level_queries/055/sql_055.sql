WITH patient_admissions AS (
        SELECT 
          p.subject_id,
          p.gender,
          p.anchor_year,
          p.anchor_age,
          a.hadm_id,
          a.admittime,
          a.dischtime,
          -- Compute birth date: anchor_year-01-01 minus anchor_age years
          DATE_SUB(CAST(CONCAT(p.anchor_year, '-01-01') AS DATE), INTERVAL p.anchor_age YEAR) AS birth_date
        FROM `physionet-data.mimiciv_3_1_hosp.patients` p
        JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
          ON p.subject_id = a.subject_id
        WHERE p.gender = 'M'
          AND p.anchor_year IS NOT NULL
          AND p.anchor_age IS NOT NULL
          AND a.dischtime IS NOT NULL
      ),
      admissions_with_age AS (
        SELECT 
          *,
          TIMESTAMP_DIFF(admittime, birth_date, YEAR) AS age_at_admission
        FROM patient_admissions
      ),
      filtered_admissions AS (
        SELECT 
          a.*,
          d.icd_code
        FROM admissions_with_age a
        JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
          ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
        WHERE a.age_at_admission BETWEEN 37 AND 47
          AND d.seq_num = 1
          AND d.icd_version = 10
          AND d.icd_code LIKE 'N17.%'
      ),
      los AS (
        SELECT 
          TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los_days
        FROM filtered_admissions
      )
      SELECT APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los
      FROM los;