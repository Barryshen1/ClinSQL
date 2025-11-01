WITH FirstAdmissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
    AND a.hadm_id IN (
      SELECT
        min(hadm_id)
      FROM
        `physionet-data.mimiciv_3_1_hosp.admissions`
      WHERE
        subject_id = a.subject_id
      GROUP BY
        subject_id
    )
)
SELECT
  STDDEV(DATE_DIFF(dischtime, admittime, DAY)) AS sd_length_of_stay_days
FROM
  FirstAdmissions;