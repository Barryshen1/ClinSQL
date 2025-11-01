WITH
  PatientCohort AS (
    SELECT
      p.subject_id,
      p.gender,
      p.anchor_age AS age,
      a.admittime,
      a.hadm_id,
      -- Check for T2DM diagnosis
      CASE
        WHEN EXISTS (
          SELECT
            1
          FROM
            `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
          WHERE
            d.subject_id = p.subject_id AND d.icd_code LIKE 'E11%'
        ) THEN 1
        ELSE 0
      END AS has_t2dm,
      -- Check for HF diagnosis
      CASE
        WHEN EXISTS (
          SELECT
            1
          FROM
            `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
          WHERE
            d.subject_id = p.subject_id AND d.icd_code LIKE 'I50%'
          OR d.icd_code LIKE 'I11%'
          OR d.icd_code LIKE 'I13%'
        ) THEN 1
        ELSE 0
      END AS has_hf
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
    JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON p.subject_id = a.subject_id
    WHERE
      p.gender = 'F' AND p.anchor_age BETWEEN 67 AND 77
  ),
  FirstMedication AS (
    SELECT
      subject_id,
      hadm_id,
      MIN(charttime) AS first_med_time,
      MIN(CASE WHEN drug_class IN ('insulin', 'metformin', 'sulfonylurea', 'dpp4', 'sglt2', 'glp1', 'tzd') THEN 1 ELSE 0 END) AS first_med_flag
    FROM
      `physionet-data.mimiciv_3_1_hosp.emar` AS e
    JOIN
      `physionet-data.mimiciv_3_1_hosp.emar_detail` AS ed
      ON e.emar_id = ed.emar_id
    WHERE
      ed.medication IN ('insulin', 'metformin', 'sulfonylurea', 'dpp4', 'sglt2', 'glp1', 'tzd')
    GROUP BY
      subject_id,
      hadm_id
  ),
  MedicationInitiation AS (
    SELECT
      pc.subject_id,
      pc.hadm_id,
      fm.first_med_time,
      e.charttime,
      e.medication AS drug_class
    FROM
      PatientCohort AS pc
    JOIN
      FirstMedication AS fm
      ON pc.subject_id = fm.subject_id AND pc.hadm_id = fm.hadm_id
    JOIN
      `physionet-data.mimiciv_3_1_hosp.emar` AS e
      ON pc.subject_id = e.subject_id AND pc.hadm_id = e.hadm_id
    JOIN
      `physionet-data.mimiciv_3_1_hosp.emar_detail` AS ed
      ON e.emar_id = ed.emar_id
    WHERE
      pc.has_t2dm = 1 AND pc.has_hf = 1
      AND ed.medication IN ('insulin', 'metformin', 'sulfonylurea', 'dpp4', 'sglt2', 'glp1', 'tzd')
      AND e.charttime <= TIMESTAMP_ADD(fm.first_med_time, INTERVAL 12 HOUR)
  )
SELECT
  drug_class,
  COUNT(subject_id) AS initiation_count
FROM
  MedicationInitiation
GROUP BY
  drug_class;