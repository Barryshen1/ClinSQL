SELECT
  SAFE_DIVIDE(100.0 * COUNTIF(avg_sbp <= 160), COUNT(*)) AS percentile
FROM (
  SELECT
    ce.stay_id,
    AVG(ce.valuenum) AS avg_sbp
  FROM
    `physionet-data.mimiciv_3_1_icu`.chartevents ce
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu`.d_items di
    ON ce.itemid = di.itemid
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu`.icustays icu
    ON ce.stay_id = icu.stay_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.patients p
    ON icu.subject_id = p.subject_id
  WHERE
    di.label IN ('NIBP Systolic', 'Arterial BP Systolic')
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= icu.intime
    AND ce.charttime < DATETIME_ADD(icu.intime, INTERVAL 48 HOUR)
    AND p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM icu.intime) - p.anchor_year)) BETWEEN 77 AND 87
  GROUP BY
    ce.stay_id
  HAVING
    AVG(ce.valuenum) IS NOT NULL
) avg_bp;