WITH PneumoniaPatients AS (
  SELECT DISTINCT
    p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    p.gender = 'F' AND d.icd_code = 'J18.9' -- J18.9 is the ICD-10 code for Pneumonia, unspecified organism
),
CreatinineMeasurements AS (
  SELECT
    subject_id,
    charttime,
    valuenum AS creatinine_value
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
    ON le.itemid = dli.itemid
  WHERE
    dli.label = 'Creatinine'
),
HourlyCreatinine AS (
  SELECT
    subject_id,
    DATE(charttime) AS chart_date,
    AVG(creatinine_value) AS avg_hourly_creatinine
  FROM
    CreatinineMeasurements
  GROUP BY
    subject_id,
    chart_date
),
DailyAverageCreatinine AS (
  SELECT
    subject_id,
    chart_date,
    AVG(avg_hourly_creatinine) AS daily_avg_creatinine
  FROM
    HourlyCreatinine
  GROUP BY
    subject_id,
    chart_date
)
SELECT
  MIN(daily_avg_creatinine) AS min_24hr_avg_creatinine
FROM
  DailyAverageCreatinine
WHERE
  subject_id IN (
    SELECT
      subject_id
    FROM
      PneumoniaPatients
  );