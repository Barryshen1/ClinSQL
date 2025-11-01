WITH valve_procedures AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
   AND p.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON a.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS d
    ON p.icd_code = d.icd_code
   AND p.icd_version = d.icd_version
  WHERE
    LOWER(d.long_title) LIKE '%valve%'
    AND (
          LOWER(d.long_title) LIKE '%replacement%'
          OR LOWER(d.long_title) LIKE '%repair%'
          OR LOWER(d.long_title) LIKE '%annuloplasty%'
          OR LOWER(d.long_title) LIKE '%valvuloplasty%'
        )
    -- Age at admission: anchor_age + (year(admittime) - anchor_year)
    AND pat.anchor_age IS NOT NULL
    AND pat.anchor_year IS NOT NULL
    AND (pat.anchor_age + (EXTRACT(YEAR FROM a.admittime) - pat.anchor_year)) BETWEEN 42 AND 52
    AND UPPER(pat.gender) = 'M'
)

SELECT
  AVG(distinct_valve_procs) AS avg_distinct_valve_procs_per_patient
FROM (
  SELECT
    subject_id,
    COUNT(DISTINCT CONCAT(CAST(hadm_id AS STRING), '|', icd_code)) AS distinct_valve_procs
  FROM valve_procedures
  GROUP BY subject_id
) t;