WITH cohort AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.los,
    i.intime,
    p.gender,
    p.anchor_age,
    a.hospital_expire_flag
  FROM (
    SELECT *,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu`.icustays
  ) i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
    ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON i.hadm_id = a.hadm_id
  WHERE i.rn = 1
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 76 AND 86
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d
      WHERE d.hadm_id = i.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '410%')
          OR
          (d.icd_version = 10 AND d.icd_code LIKE 'I21%')
        )
    )
),
procedures AS (
  SELECT
    c.stay_id,
    COUNT(DISTINCT pe.itemid) AS procedure_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu`.procedureevents pe
    ON pe.stay_id = c.stay_id
    AND pe.itemid IS NOT NULL
    AND pe.starttime >= c.intime
    AND pe.starttime < DATETIME_ADD(c.intime, INTERVAL 1 DAY)
  GROUP BY c.stay_id
),
enriched AS (
  SELECT
    c.*,
    COALESCE(pr.procedure_count, 0) AS procedure_count
  FROM cohort c
  LEFT JOIN procedures pr
    ON pr.stay_id = c.stay_id
),
quartiled AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY procedure_count) AS quartile
  FROM enriched
)
SELECT
  quartile,
  ROUND(AVG(procedure_count), 2) AS mean_procedure_count,
  ROUND(AVG(los), 2) AS mean_icu_los,
  ROUND((SUM(hospital_expire_flag) * 100.0 / COUNT(*)), 2) AS hospital_mortality_pct
FROM quartiled
GROUP BY quartile
ORDER BY quartile;