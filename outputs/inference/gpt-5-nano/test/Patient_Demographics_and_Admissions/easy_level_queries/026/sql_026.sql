WITH first_adm AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN (
    SELECT
      subject_id,
      MIN(admittime) AS first_admittime
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions`
    GROUP BY
      subject_id
  ) m
    ON a.subject_id = m.subject_id
   AND a.admittime = m.first_admittime
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 48 AND 58
),

cabg_in_first AS (
  SELECT DISTINCT
    fa.subject_id,
    fa.hadm_id
  FROM
    first_adm fa
  JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pc
    ON fa.subject_id = pc.subject_id
   AND fa.hadm_id = pc.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` di
    ON pc.icd_code = di.icd_code
   AND pc.icd_version = di.icd_version
  WHERE
    LOWER(di.long_title) LIKE '%cabg%'
    OR LOWER(di.long_title) LIKE '%coronary artery bypass graft%'
)

, mortality AS (
  -- Force mortality to a numeric INT64 to ensure proper input type for APPROX_QUANTILES
  SELECT
    CAST(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END AS INT64) AS mortality
  FROM cabg_in_first c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON c.hadm_id = a.hadm_id
)

SELECT
  CAST(v AS INT64) AS p25_mortality
FROM (
  SELECT APPROX_QUANTILES(mortality, 4) AS q
  FROM mortality
) t
CROSS JOIN
  UNNEST(t.q) AS v WITH OFFSET AS idx
WHERE idx = 0;