WITH cohort AS (
  SELECT
    p.subject_id,
    i.stay_id,
    i.los AS icu_los,
    a.hospital_expire_flag,
    i.intime AS icu_intime
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions a
      ON p.subject_id = a.subject_id
  JOIN
    physionet-data.mimiciv_3_1_icu.icustays i
      ON a.hadm_id = i.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
      ON a.hadm_id = d.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 65 AND 75
    AND LOWER(dd.long_title) LIKE '%pulmonary embolism%'
    AND i.stay_id IN (
      SELECT stay_id
      FROM (
        SELECT stay_id, ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
        FROM physionet-data.mimiciv_3_1_icu.icustays
      ) ranked
      WHERE rn = 1
    )
),

procedures_in_72h AS (
  SELECT
    c.stay_id,
    COUNT(*) AS procedure_count
  FROM
    cohort c
  JOIN
    physionet-data.mimiciv_3_1_icu.procedureevents pe
      ON c.stay_id = pe.stay_id
  JOIN
    physionet-data.mimiciv_3_1_icu.d_items di
      ON pe.itemid = di.itemid
  WHERE
    pe.starttime >= c.icu_intime
    AND pe.starttime <= DATETIME_ADD(c.icu_intime, INTERVAL 72 HOUR)
    AND di.category = 'Procedures'
  GROUP BY
    c.stay_id
),

quartiles AS (
  SELECT
    c.stay_id,
    COALESCE(p.procedure_count, 0) AS procedure_count,
    c.icu_los,
    c.hospital_expire_flag,
    NTILE(4) OVER (ORDER BY COALESCE(p.procedure_count, 0)) AS quartile
  FROM
    cohort c
  LEFT JOIN
    procedures_in_72h p
      ON c.stay_id = p.stay_id
)

SELECT
  quartile,
  COUNT(*) AS n,
  AVG(procedure_count) AS mean_procedure_count,
  AVG(icu_los) AS mean_icu_los_days,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS hospital_mortality_percent
FROM
  quartiles
GROUP BY
  quartile
ORDER BY
  quartile;